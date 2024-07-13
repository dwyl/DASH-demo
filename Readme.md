# MPEG-DASH with Elixir and Livebook

This repo demonstrates how to use the **D**ynamic **A**daptative **S**treaming over **H**TTP with a Livebook or by forking this repo.

We essentially use `FFmpeg` to build the DASH files (segments and a manifest file) and teh Javascript library [`dash.js`](https://github.com/Dash-Industry-Forum/dash.js).

You can fork the repo and run this code with `mix run --no-halt` or run the `Livebook` below.

## What is DASH?

[DASH](https://www.mpeg.org/standards/MPEG-DASH/)

DASH can be compared to `HLS`. This [repo](https://github.com/dwyl/HLS-demo) illustrates a usage of HLS with insertion of face recognition.

### What is adaptative?

This means you produce video files with different quality levels, low, medium or high for example. This is done by invoquing the adequate FFmpeg command.

We did not illustrate this here.

### Video containers and codecs and browsers

Video files use "containers" such a WEBM or MP4. Each use different codecs, and normally VP8/VP9 for the first, and H264/H265 (aka AV1) for the second for the video track.

Typically, when you record your webcam feed, you use the [`MediaRecorder` API](https://developer.mozilla.org/en-US/docs/Web/API/MediaRecorder).

You can pass an option to specify the mimeType and codec. For example:

```js
const options = { mimeType: "video/mp4; codecs=avc1.42E01E" };
// or
const options = { mimeType: 'video/mp4; codecs="avc1.424028, mp4a.40.2"' };
// or
const options = { mimType: "video/webm; codecs=vp8" };
//
const options = { mimeType: "video/Webm; codec=vp9" };
```

and use it:

```js
let mediaRecorder = new MediaRecorder(stream, options);
```

The evolution of codecs tend to produce smaller files or support 4K or 8k but at the expense of encoding time. Furthermore, some codecs are patented thus you may pay royalties to use them.

Thus the MediaRecorder in the browser might not be able to produce multimedia files (video & audio) in the given format or not be able to use the given codec.

For example:

- Safari does not support WebM for MediaRecorder but supports MP4.
- Firefox does not support MP4 with MediaRecorder.
- Chrome supports MP4 for MediaRecorder with some difficulties.
- Chrome and Firefox support WebM with hte codec VP8. Only Chrome supports the codec VP9, but not the successor AV1.

### Video formats, a brief summary

Different format of video formats you can encounter.

1. MP4 (MPEG-4)
   Container Format: stores video and audio.
   Video codecs: H.264 (AVC), H.265 (HEVC)
   Audio codecs: AAC, MP3

2. WebM
   Container Format: WebM is an open, royalty-free media file format designed for the web.
   Video codecs: VP8, VP9, AV1
   Audio codecs: Vorbis, Opus

3. MKV (Matroska)
   Container Format: MKV is an open standard free container format.
   Video codecs: Any, but commonly H.264/AVC, H.265/HEVC, VP8, VP9
   Audio codecs: AAC, MP3, Vorbis, FLAC

4. AVI (Audio Video Interleave)
   Container Format: AVI (Microsoft)
   Video codecs: DivX, Xvid, H.264
   Audio codecs: MP3, AC-3
   Older format, less efficient compression compared to MP4 and WebM, widely supported.

5. MOV
   Container Format: MOV is a multimedia container format developed by Apple.
   Video codecs: H.264 (AVC), H.265 (HEVC), ProRes
   Audio codecs: AAC, ALAC
   Features: Native to Apple devices, commonly used in professional video editing.

6. IVF (Indeo Video File)
   Container Format: IVF is a simple container format primarily used for encapsulating VP8 and VP9 video streams. Typically does not include Audio. Used for testing and development purposes.
   Video codecs: VP8, VP9

7. TS (Transport Stream), for HLS
   It is packet based format (packets of length 168 bytes). It can multiplex (combine) multiple audio, video, and data streams into a single stream, allowing synchronized playback.
   It has a built-in Error Correction mechanisms to improve reliability over unreliable transmission mediums.
   Video codecs: H.264 (AVC), H.265 (HEVC)
   Audio codecs: AAC, AC3

## How can we solve this?

You may want to detect the user-agent in the browser. The [MDN documentation](https://developer.mozilla.org/en-US/docs/Web/HTTP/Browser_detection_using_the_user_agent) strongly discourages this route and recommends to find an alternative.

The `MediaRecorder` has a static method [isTtypeSupported()](https://developer.mozilla.org/en-US/docs/Web/API/MediaRecorder/isTypeSupported_static) to check whether it can support a given `mimeType`. We will use this.

We pass the type in the query string of WebSocket connection (for the repo only, not the Livebook where we did it differently).

In the Elixir router, we capture the type and run the adequate `FFmpeg` command.

We need the WebSocket handler to get the PID of the FFmpeg process. We use an `:ets` table for this.

In code, this gives:

```js
let mediaRecorder, mimetype;
const types = [
  "video/mp4; codecs=avc1.42E01E, mp4a.40.2",
  "video/mp4; codecs=avc1.64001F, mp4a.40.2",
  "video/mp4; codec=avc1.4D401F mp4a.40.2",
  "video/webm;codecs=vp8, opus",
  "video/webm;codecs=vp9, opus",
];

for (const type of types) {
  if (MediaRecorder.isTypeSupported(type)) {
    console.log(type);
    mimetype = type.split(";")[0];
    mediaRecorder = new MediaRecorder(stream, { mimeType: mimetype });
  }
}

let socket = new WebSocket(
  `ws://localhost:4000/socket?csrf_token=${csrfToken}`
);

socket.onopen = () => {
  socket.send(JSON.stringify({ mimetype }));
};
```

> Safari accepts only MP4,
> Chrome accepts WEBM and MP4 (with difficulties),
> Firefox only WEBM.

The Websocket handler is:

```elixir
defmodule WebSocketHandler do
  @moduledoc false
  @behaviour WebSock
  require Logger

  @impl true
  def init(_args) do
    dash_path = "priv/dash"
    {:ok, pid_watcher} = GenServer.start(FileWatcher, [self(), dash_path])

    state = %{
      pid_watcher: pid_watcher,
      pid_build: nil,
      init: true
    }

    {:ok, state}
  end

  def handle_in(msg, [:opcode: :text], state) do
    case Jason.decode(msg) do
      {:ok, %{"mimetype" => mimetype}} ->
        Logger.warning("MIMETYPE: #{mimetype}")
        {:ok, pid_build} = FFmpegProcessor.start(state.dash_path, mimetype)
        {:ok, %{state | pid_build: pid_build}}
      {:error, msg} ->
        Logger.warning("ERROR: #{inspect(msg)}")
        {:stop, :shutdown, state}
    end
  end
```

where we pass the mime-type to the FFmpegProcessor:

```elixir
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
```

When we receive data from the browser (a video chunk), with:

```js
mediaRecorder.ondataavailable = async ({ data }) => {
  if (!isReady) return;
  if (data.size > 0) {
    console.log(data.size);
    const buffer = await data.arrayBuffer();
    if (socket.readyState === WebSocket.OPEN) {
      socket.send(buffer);
    }
  }
};
```

we call the FFmpeg process:

```elixir
def handle_in({msg, [opcode: :binary]}, state) do
  Logger.debug("received data ---------------")
  %{pid_build: pid_build} = state
  # Write the received binary data to the FFmpeg capture process
  :ok = ExCmd.Process.write(pid_build, msg)
  {:ok, state}
end
```

One difficulty is to get the right FFmpeg command, especially in the case of Chrome with mp4.
The command can be simplified when we change the order of the "types" array. When coded as above, the last "true" codec will be used, so "VP9" in case of Chrome, and "vp8" for Firefox", and "avc1" for Safari.

The simplified FFmpeg command is:

```elixir
build_cmd_mp4 =
  ~w(ffmpeg
  -analyzeduration 100M -probesize 50M
  -i pipe:0
  -map 0
  -codec: copy
  -f dash
  -use_timeline 1
  -use_template 1
  -init_seg_name init_$RepresentationID$.m4s
  -media_seg_name chunk_$RepresentationID$_$Number$.m4s
  #{manifest}
)
```

## Run this

You can fork and run this code with `mix run --no-halt`.

You can also run this Livebook.
The code is adapted and is a nice illustration on how to use `Kino.JS.Live`.
:exclamation:
