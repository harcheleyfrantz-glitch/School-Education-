extends Node
## Times the procedural audio synthesis and writes the generated sounds to WAV files for listening.


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	Audio.call("_ensure_assets")
	print("assets: %d ms" % (Time.get_ticks_msec() - t0))
	t0 = Time.get_ticks_msec()
	var m: AudioStreamWAV = Audio._pad_music()
	print("music: %d ms" % (Time.get_ticks_msec() - t0))
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else ""
	if out != "":
		for k in Audio._loops.keys():
			(Audio._loops[k] as AudioStreamWAV).save_to_wav("%s/loop_%s.wav" % [out, k])
		for k in Audio._shots.keys():
			(Audio._shots[k] as AudioStreamWAV).save_to_wav("%s/shot_%s.wav" % [out, k])
		m.save_to_wav("%s/music.wav" % out)
	get_tree().quit()
