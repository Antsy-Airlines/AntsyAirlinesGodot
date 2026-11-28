class_name SoundCuePlayer
extends AudioStreamPlayer3D
## A 3D sound player for plane parts: plays one cue at a time, optionally offset to line up with an animation.
## A new cue (or `cancel`) stops the one playing and drops one still waiting, so a part that turns around
## mid-move never plays a stale sound. Silent on a dedicated server.
## Callers play cues from their `_set_*` RPCs, which already run on every computer, so nothing extra is synced.

# Declaring tracking variables
var _wait: Tween # waits out a positive offset before playing, if one is pending


func play_cue(cue: AudioStream, offset: float = 0.0) -> void:
	## This function plays a cue in place of whatever this player was doing
	# cue: the sound to play (null = just go quiet)
	# offset: seconds; > 0 waits before playing, < 0 skips that far into the sound
	cancel()
	# Guard case for no sound, or a dedicated server with nobody to hear it
	if cue == null or HighLevelNetworkHandler.is_server_launch():
		return

	# Guard case for a cue that plays straight away
	if offset <= 0.0:
		_start(cue, -offset)
		return

	# a tween on this node, so the wait dies with it if the plane is freed
	_wait = create_tween()
	_wait.tween_callback(_start.bind(cue, 0.0)).set_delay(offset)


func cancel() -> void:
	## This function stops the cue playing and drops one still waiting
	if _wait != null:
		_wait.kill()
		_wait = null
	stop()


func _start(cue: AudioStream, from: float) -> void:
	## This function starts a cue now
	# cue: the sound to play
	# from: seconds into the sound to start at
	_wait = null
	stream = cue
	play(from)
