$(document).ready(function(){
    window.addEventListener('message', function(event) {
        var data = event.data;

		if (data.type == "playAudio") {

			playAudio(data.audioFileName, data.volume)
		}
    });
	function playAudio(audioFileName, volume) {
		var audio = new Audio('assets/audio/'+audioFileName);
		audio.volume = volume;
  		audio.play();
	};
});