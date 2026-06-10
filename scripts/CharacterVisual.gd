# CharacterVisual.gd
# Runtime-assembled animated character using the Mixamo-style FBX set in
# assets/Character. One FBX per animation, shared skeleton:
#   PB_IDLE / PB_Run_* / PB_Smash_* / PB_Victory / PB_Defeat + Paddle_bat.
#
# Defensive by design: if the FBX files haven't been imported by the editor
# yet (or the rig differs), setup() returns false and the caller keeps its
# placeholder visuals.
class_name CharacterVisual
extends Node3D

const BASE_MODEL_PATH := "res://assets/Character/PB_IDLE.fbx"
const PADDLE_PATH := "res://assets/Character/Paddle_bat.fbx"
# Clean name -> source FBX. The animation inside each file is renamed on
# extraction so gameplay code uses readable names.
const ANIM_SOURCES := {
	"idle": "res://assets/Character/PB_IDLE.fbx",
	"run_forward": "res://assets/Character/PB_Run_Forward.fbx",
	"run_backward": "res://assets/Character/PB_Run_Backward.fbx",
	"run_left": "res://assets/Character/PB_Run_Left.fbx",
	"run_right": "res://assets/Character/PB_Run_Right.fbx",
	"smash_left": "res://assets/Character/PB_Smash_Left.fbx",
	"smash_right": "res://assets/Character/PB_Smash_Right.fbx",
	"victory": "res://assets/Character/PB_Victory.fbx",
	"defeat": "res://assets/Character/PB_Defeat.fbx",
}
const LOOPED_ANIMS := ["idle", "run_forward", "run_backward", "run_left", "run_right"]

# Desired character height in world units. The court is ~half real-world
# scale (3.0 wide vs 6.1 m real), so a 1.8 m human ≈ 0.9 units.
@export var target_height: float = 0.9
# Mixamo rigs face +Z as authored, which is already "toward the net" for a
# root with yaw 0 in our convention — no offset needed. Flip to PI if a
# different rig faces backwards.
@export var model_yaw_offset: float = 0.0

var anim_player: AnimationPlayer = null
var model: Node3D = null
var skeleton: Skeleton3D = null
var is_ready: bool = false

# Name of the one-shot animation currently playing (smash/victory/defeat).
# While set, run/idle requests are ignored so the swing doesn't get cut off.
var _oneshot_playing: String = ""


func setup() -> bool:
	var base_scene: PackedScene = load(BASE_MODEL_PATH)
	if base_scene == null:
		push_warning("CharacterVisual: %s not imported yet — keeping placeholder." % BASE_MODEL_PATH)
		return false

	model = base_scene.instantiate()
	add_child(model)
	model.rotation.y = model_yaw_offset

	anim_player = _find_anim_player(model)
	skeleton = _find_skeleton(model)
	if anim_player == null or skeleton == null:
		push_warning("CharacterVisual: base FBX has no AnimationPlayer/Skeleton3D.")
		model.queue_free()
		model = null
		return false

	_autoscale_model()
	_collect_animations()
	_attach_paddle()

	anim_player.playback_default_blend_time = 0.15
	anim_player.animation_finished.connect(_on_animation_finished)
	is_ready = true
	play("idle")
	return true


# === PUBLIC API ===

func play(anim_name: String) -> void:
	if not is_ready or _oneshot_playing != "":
		return
	if anim_player.has_animation(anim_name) and anim_player.current_animation != anim_name:
		anim_player.play(anim_name)

# Movement-driven locomotion. `local_dir` is the movement direction in the
# character's own frame: +z forward (toward the net), +x to their right.
func update_locomotion(local_dir: Vector3, speed: float) -> void:
	if not is_ready or _oneshot_playing != "":
		return
	if speed < 0.15:
		play("idle")
		return
	if absf(local_dir.x) > absf(local_dir.z):
		play("run_right" if local_dir.x > 0.0 else "run_left")
	else:
		play("run_forward" if local_dir.z > 0.0 else "run_backward")

# side > 0 → ball on character's right side.
func play_smash(side: float) -> void:
	_play_oneshot("smash_right" if side >= 0.0 else "smash_left")

func play_victory() -> void:
	_play_oneshot("victory")

func play_defeat() -> void:
	_play_oneshot("defeat")

func reset_to_idle() -> void:
	_oneshot_playing = ""
	if is_ready:
		anim_player.play("idle")


# === INTERNAL ===

func _play_oneshot(anim_name: String) -> void:
	if not is_ready:
		return
	if anim_player.has_animation(anim_name):
		_oneshot_playing = anim_name
		anim_player.play(anim_name)

func _on_animation_finished(finished: StringName) -> void:
	if String(finished) == _oneshot_playing:
		_oneshot_playing = ""
		anim_player.play("idle")

func _find_anim_player(root: Node) -> AnimationPlayer:
	var found: Array[Node] = root.find_children("*", "AnimationPlayer", true, false)
	return found[0] as AnimationPlayer if found.size() > 0 else null

func _find_skeleton(root: Node) -> Skeleton3D:
	var found: Array[Node] = root.find_children("*", "Skeleton3D", true, false)
	return found[0] as Skeleton3D if found.size() > 0 else null

func _autoscale_model() -> void:
	# Measure the model's combined AABB and scale it to target_height, so the
	# import scale (cm vs m) doesn't matter. Clamped + logged because a bad
	# measurement here produces a skyscraper that shadows the whole court.
	var aabb: AABB = _combined_aabb(model)
	print("CharacterVisual: raw model height = %.3f" % aabb.size.y)
	var s: float = 0.5  # sane fallback for a metre-scale rig
	if aabb.size.y > 0.001:
		s = clampf(target_height / aabb.size.y, 0.001, 10.0)
	model.scale = Vector3(s, s, s)
	print("CharacterVisual: applied model scale = %.4f" % s)

func _combined_aabb(root: Node) -> AABB:
	var result: AABB = AABB()
	var first: bool = true
	for mesh_node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = mesh_node as MeshInstance3D
		var transformed: AABB = mi.global_transform * mi.get_aabb()
		if first:
			result = transformed
			first = false
		else:
			result = result.merge(transformed)
	return result

func _collect_animations() -> void:
	# Pull the (single) animation out of every source FBX into the base
	# model's AnimationPlayer, renamed to our clean names.
	#
	# The imported AnimationPlayer already owns a default "" library (with
	# the FBX's own take) — reuse it; adding a second library named ""
	# would fail and leave us with zero animations (frozen bind pose).
	var lib: AnimationLibrary
	if anim_player.has_animation_library(""):
		lib = anim_player.get_animation_library("")
	else:
		lib = AnimationLibrary.new()
		anim_player.add_animation_library("", lib)

	# All animation track paths must point at OUR skeleton. Tracks exported
	# from the other FBX files reference their own scene's node names, so we
	# rewrite every bone track onto the base model's skeleton path.
	var anim_root: Node = anim_player.get_node(anim_player.root_node)
	var skel_path: String = String(anim_root.get_path_to(skeleton))

	for clean_name: String in ANIM_SOURCES:
		var anim: Animation = _extract_animation(ANIM_SOURCES[clean_name])
		if anim == null:
			push_warning("CharacterVisual: no animation in %s" % ANIM_SOURCES[clean_name])
			continue
		_remap_tracks_to_skeleton(anim, skel_path)
		if clean_name in LOOPED_ANIMS:
			anim.loop_mode = Animation.LOOP_LINEAR
		else:
			# One-shots (smash/victory/defeat): Mixamo bakes root motion into
			# the hips. The lunge slides the character away from its gameplay
			# position, then the blend back to idle snaps it home — reads as
			# a flicker. Keep vertical hip motion (the squat), pin X/Z.
			_strip_horizontal_root_motion(anim)
		if lib.has_animation(clean_name):
			lib.remove_animation(clean_name)
		lib.add_animation(clean_name, anim)
	print("CharacterVisual: animations ready → ", anim_player.get_animation_list())

func _strip_horizontal_root_motion(anim: Animation) -> void:
	for i: int in anim.get_track_count():
		if anim.track_get_type(i) != Animation.TYPE_POSITION_3D:
			continue
		var bone: String = anim.track_get_path(i).get_concatenated_subnames().to_lower()
		if not bone.contains("hips"):
			continue
		var key_count: int = anim.track_get_key_count(i)
		if key_count == 0:
			continue
		var first: Vector3 = anim.track_get_key_value(i, 0)
		for k: int in key_count:
			var v: Vector3 = anim.track_get_key_value(i, k)
			anim.track_set_key_value(i, k, Vector3(first.x, v.y, first.z))

func _remap_tracks_to_skeleton(anim: Animation, skel_path: String) -> void:
	# Bone tracks are "path/to/Skeleton3D:bone_name". Keep the bone part,
	# replace the node part with our skeleton's path.
	for i: int in anim.get_track_count():
		var old_path: NodePath = anim.track_get_path(i)
		var bone: String = old_path.get_concatenated_subnames()
		if bone != "":
			anim.track_set_path(i, NodePath(skel_path + ":" + bone))

func _extract_animation(path: String) -> Animation:
	var scene: PackedScene = load(path)
	if scene == null:
		return null
	var inst: Node = scene.instantiate()
	var src_player: AnimationPlayer = _find_anim_player(inst)
	var result: Animation = null
	if src_player != null:
		var names: PackedStringArray = src_player.get_animation_list()
		if names.size() > 0:
			# Take the first (Mixamo exports exactly one per file).
			result = src_player.get_animation(names[0]).duplicate(true)
	inst.queue_free()
	return result

func _attach_paddle() -> void:
	var bone_idx: int = _find_hand_bone()
	if bone_idx < 0:
		push_warning("CharacterVisual: no hand bone found. Bones: %s" % ", ".join(_all_bone_names()))
		return
	print("CharacterVisual: paddle bone = ", skeleton.get_bone_name(bone_idx))
	var attachment: BoneAttachment3D = BoneAttachment3D.new()
	attachment.bone_name = skeleton.get_bone_name(bone_idx)
	skeleton.add_child(attachment)

	var paddle: Node3D = null
	var paddle_scene: PackedScene = load(PADDLE_PATH)
	if paddle_scene != null:
		paddle = paddle_scene.instantiate()
		attachment.add_child(paddle)
		# Auto-scale in WORLD space so a unit mismatch between the paddle FBX
		# and the rig (cm vs m) can't produce a court-sized or invisible
		# paddle. Real paddle ≈ 0.4 m vs 1.8 m human → ~22% of height.
		var paddle_aabb: AABB = _combined_aabb(paddle)
		var longest: float = maxf(paddle_aabb.size.x, maxf(paddle_aabb.size.y, paddle_aabb.size.z))
		print("CharacterVisual: raw paddle longest axis (world) = %.4f" % longest)
		if longest > 0.0001:
			var desired: float = 0.22 * target_height
			var ps: float = clampf(desired / longest, 0.0001, 1000.0)
			paddle.scale = paddle.scale * ps
			print("CharacterVisual: applied paddle scale = %.4f" % ps)
		else:
			# Degenerate import — drop it and use the fallback below.
			paddle.queue_free()
			paddle = null
	if paddle == null:
		# Guaranteed-visible fallback: a simple primitive paddle so the
		# character is never empty-handed even if the FBX fails.
		paddle = _build_primitive_paddle()
		attachment.add_child(paddle)
		print("CharacterVisual: using primitive fallback paddle")

func _build_primitive_paddle() -> Node3D:
	var root := Node3D.new()
	root.name = "FallbackPaddle"
	# Sizes are authored in world units, then counter-scaled because the
	# attachment inherits the model's scale through the skeleton.
	var inv: float = 1.0
	if model and model.scale.x > 0.0001:
		inv = 1.0 / model.scale.x
	root.scale = Vector3(inv, inv, inv)

	var face := MeshInstance3D.new()
	var face_mesh := BoxMesh.new()
	face_mesh.size = Vector3(0.10, 0.13, 0.02)
	face.mesh = face_mesh
	face.position = Vector3(0, 0.13, 0)
	var handle := MeshInstance3D.new()
	var handle_mesh := CylinderMesh.new()
	handle_mesh.top_radius = 0.012
	handle_mesh.bottom_radius = 0.012
	handle_mesh.height = 0.09
	handle.mesh = handle_mesh
	handle.position = Vector3(0, 0.045, 0)
	root.add_child(face)
	root.add_child(handle)
	return root

func _find_hand_bone() -> int:
	# Try hard to find a right hand across naming conventions:
	# mixamorig_RightHand, Hand.R, hand_r, R_Hand, RightHand, etc.
	var hand_bones: Array[int] = []
	for i: int in skeleton.get_bone_count():
		var raw: String = skeleton.get_bone_name(i).to_lower()
		var norm: String = ""
		for ch in raw:
			if ch >= "a" and ch <= "z":
				norm += ch
		if norm.contains("hand") and not norm.contains("thumb") \
			and not norm.contains("index") and not norm.contains("middle") \
			and not norm.contains("ring") and not norm.contains("pinky"):
			hand_bones.append(i)
	# Prefer an explicit right hand.
	for i: int in hand_bones:
		var raw: String = skeleton.get_bone_name(i).to_lower()
		if raw.contains("right") or raw.ends_with(".r") or raw.ends_with("_r") or raw.begins_with("r_"):
			return i
	# Otherwise take any hand.
	return hand_bones[0] if hand_bones.size() > 0 else -1

func _all_bone_names() -> PackedStringArray:
	var names := PackedStringArray()
	for i: int in skeleton.get_bone_count():
		names.append(skeleton.get_bone_name(i))
	return names
