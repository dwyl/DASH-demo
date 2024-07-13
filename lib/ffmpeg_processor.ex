
defmodule FFmpegProcessor do
  @moduledoc false

  def start(path, mimetype) do

    manifest = Path.join(path, "manifest.mpd")

    build_cmd_webm = 
      ~w(ffmpeg -i pipe:0 
        -map 0
        -codec: copy
        -f dash
        -use_timeline 1
        -use_template 1
        -init_seg_name init_$RepresentationID$.webm
        -media_seg_name chunk_$RepresentationID$_$Number$.webm
        #{manifest}
      )

      # -codec: copy
      build_cmd_mp4 = 
        ~w(ffmpeg 
        -analyzeduration 100M -probesize 50M
        -i pipe:0 
        -map 0
        -c:v libx264
        -preset fast
        -crf 23
        -c:a aac
        -f dash
        -use_timeline 1
        -use_template 1
        -init_seg_name init_$RepresentationID$.m4s
        -media_seg_name chunk_$RepresentationID$_$Number$.m4s
        #{manifest}
      )

    case mimetype do
      "video/mp4" -> 
        {:ok, _pid_build} = 
          ExCmd.Process.start_link(build_cmd_mp4, log: true)
      "video/webm" -> 
        {:ok, _pid_build} = 
          ExCmd.Process.start_link(build_cmd_webm, log: true)
    end
  end
end

##################################################################################
# ffmpeg [GeneralOptions] [InputFileOptions] -i input [OutputFileOptions] output #
##################################################################################
