$(function() {
  
  var progress_bar = $('<div>').width(currentPercentPlayed(current_pos,current_duration)).appendTo('#progress');
  
  if(current_state == 'run') var updater = window.setInterval(updateProgress,1000);
  
  function updateProgress() {
    if((p=current_pos)<(d=current_duration)) {
      current_pos += 1;
      progress_bar.width(currentPercentPlayed(p,d)); 
    }
    else {
      clearInterval(updater);
      location.reload();
    }
  }
  
  function currentPercentPlayed(p,d) {
    return((p / d) * 100 + '%');
  }
  
  function prettyTrackLength(s) {
    m = Math.floor(s / 60);
    s = s % 60;
    return m + ':' + s;
  }
});