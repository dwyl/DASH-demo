document.addEventListener("DOMContentLoaded", async function () {
  const csrfToken = document
    .querySelector("meta[name='csrf-token']")
    .getAttribute("content");

  let video1 = document.getElementById("source"),
    video2 = document.getElementById("output"),
    spinner = document.getElementById("spinner"),
    fileProc = document.getElementById("file-proc"),
    stop = document.getElementById("stop"),
    isReady = false;

  let stream = await navigator.mediaDevices.getUserMedia({
    video: { width: 640, height: 480 },
    audio: false,
  });

  video1.srcObject = stream;
  spinner.style.visibility = "hidden";
  video2.style.visibility = "hidden";

  let mediaRecorder, mimetype;
  const types = [
    "video/mp4; codecs=avc1.42E01E, mp4a.40.2",
    "video/mp4; codecs=avc1.64001F, mp4a.40.2",
    "video/mp4; codec=avc1.4D401F, mp4a.40.2",
    "video/webm;codecs=vp8, opus",
    "video/webm;codecs=vp9, opus",
  ];

  for (const type of types) {
    if (MediaRecorder.isTypeSupported(type)) {
      console.log(type);
      mimetype = type.split(";")[0];
      mediaRecorder = new MediaRecorder(stream, { mimeType: type });
    }
  }

  let socket = new WebSocket(
    `ws://localhost:4000/socket?csrf_token=${csrfToken}`
  );

  socket.onopen = () => {
    socket.send(JSON.stringify({ mimetype }));
  };

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

  fileProc.onclick = () => {
    isReady = true;
    if (mediaRecorder.state == "inactive") mediaRecorder.start(1_000);
    spinner.style.visibility = "visible";
  };

  stop.onclick = () => {
    mediaRecorder.stop();
    socket.send("stop");
    socket.close();
  };

  const Hls = window.Hls;

  socket.onmessage = async ({ data }) => {
    if (!data == "playlist_ready") return;
    spinner.style.visibility = "hidden";
    video2.style.visibility = "visible";

    let url = "/dash/manifest.mpd";
    let player = dashjs.MediaPlayer().create();
    player.initialize(video2, url, true);
  };
});
