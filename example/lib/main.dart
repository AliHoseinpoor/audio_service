/*
1) Play the song first
2) Press the seek button when the song is fully loaded and played
3) when AudioService.playbackStateStream == AudioProcessingState.buffering
stop the music. Here you see that positionStream gets stuck on 2 minutes
and does not become zero.(This is a bug)
4) Finally, play the song again
5) And you see that positionStream gets stuck for 2 minutes and does not start over
 */


import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  runApp(App());
}

class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'test',
      home: AudioServiceWidget(child: Test()),
    );
  }
}

class Test extends StatelessWidget {

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Center(
            child: StreamBuilder(
              stream: AudioService.positionStream,
              builder: (context, position) {
                return Text(
                  position.hasData ? (position.data as Duration).toString() : 'not initial',
                );
              },
            ),
          ),
          Center(
            child: StreamBuilder(
              stream: AudioService.playbackStateStream,
              builder: (context, playbackState) {
                return Text(
                  playbackState.hasData ? (playbackState.data as PlaybackState).processingState.toString() : 'not initial',
                );
              },
            ),
          ),
          RaisedButton(
            onPressed: () {
              AudioService.seekTo(const Duration(minutes: 2));
            },
            child: const Center(
              child: Text('seek to Duration(minute:2)'),
            ),
          ),
          RaisedButton(
            onPressed: () {
              AudioService.stop();
            },
            child: const Center(
              child: Text('stop music'),
            ),
          ),
          RaisedButton(
            onPressed: () {
              AudioService.start(
                backgroundTaskEntrypoint: _audioPlayerTaskEntrypoint,
                androidNotificationChannelName: 'Audio Service Demo',
                // Enable this if you want the Android service to exit the foreground state on pause.
                //androidStopForegroundOnPause: true,
                androidNotificationColor: 0xFF2196f3,
                androidNotificationIcon: 'mipmap/ic_launcher',
                androidEnableQueue: true,
              );
            },
            child: const Center(
              child: Text('start music'),
            ),
          ),
        ],
      ),
    );
  }
}

void _audioPlayerTaskEntrypoint() async {
  AudioServiceBackground.run(() => AudioPlayerTask());
}

//BackgroundAudioTask completly copy from pub.dev

class AudioPlayerTask extends BackgroundAudioTask {
  final AudioPlayer _player = AudioPlayer();
  AudioProcessingState _skipState;
  StreamSubscription<PlaybackEvent> _eventSubscription;

  List<MediaItem> get queue => items;

  int get index => _player.currentIndex;

  MediaItem get mediaItem => index == null ? null : queue[index];

  @override
  Future<void> onStart(Map<String, dynamic> params) async {
    _player.currentIndexStream.listen((index) {
      if (index != null) AudioServiceBackground.setMediaItem(queue[index]);
    });
    // Propagate all events from the audio player to AudioService clients.
    _eventSubscription = _player.playbackEventStream.listen((event) {
      _broadcastState();
    });
    // Special processing for state transitions.
    _player.processingStateStream.listen((state) {
      switch (state) {
        case ProcessingState.completed:
          // In this example, the service stops when reaching the end.
          onStop();
          break;
        case ProcessingState.ready:
          // If we just came from skipping between tracks, clear the skip
          // state now that we're ready to play.
          _skipState = null;
          break;
        default:
          break;
      }
    });

    // Load and broadcast the queue
    AudioServiceBackground.setQueue(queue);
    try {
      await _player.setAudioSource(ConcatenatingAudioSource(
        children: queue.map((item) => AudioSource.uri(Uri.parse(item.id))).toList(),
      ));
      // In this example, we automatically start playing on start.
      onPlay();
    } catch (e) {
      print("Error: $e");
      onStop();
    }
  }

  @override
  Future<void> onSkipToQueueItem(String mediaId) async {
    final newIndex = queue.indexWhere((item) => item.id == mediaId);
    if (newIndex == -1) return;
    _skipState = newIndex > index
        ? AudioProcessingState.skippingToNext
        : AudioProcessingState.skippingToPrevious;
    // This jumps to the beginning of the queue item at newIndex.
    _player.seek(Duration.zero, index: newIndex);
  }

  @override
  Future<void> onPlay() => _player.play();

  @override
  Future<void> onPause() => _player.pause();

  @override
  Future<void> onSeekTo(Duration position) => _player.seek(position);

  @override
  Future<void> onStop() async {
    await _player.dispose();
    _eventSubscription.cancel();
    await _broadcastState();
    print('on stop');
    return super.onStop();
  }

  /// Broadcasts the current state to all clients.
  Future<void> _broadcastState() async {
    await AudioServiceBackground.setState(
      controls: [
        MediaControl.skipToPrevious,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: [
        MediaAction.seekTo,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      ],
      // androidCompactActions: [0, 1, 3],
      processingState: _getProcessingState(),
      playing: _player.playing,
      position: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
    );
  }

  /// Maps just_audio's processing state into into audio_service's playing
  /// state. If we are in the middle of a skip, we use [_skipState] instead.
  AudioProcessingState _getProcessingState() {
    if (_skipState != null) return _skipState;
    switch (_player.processingState) {
      case ProcessingState.idle:
        return AudioProcessingState.stopped;
      case ProcessingState.loading:
        return AudioProcessingState.connecting;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
      default:
        throw Exception("Invalid state: ${_player.processingState}");
    }
  }
}

final items = <MediaItem>[
  const MediaItem(
    id: "https://s3.amazonaws.com/scifri-episodes/scifri20181123-episode.mp3",
    album: "Science Friday",
    title: "A Salute To Head-Scratching Science",
    artist: "Science Friday and WNYC Studios",
    duration: Duration(milliseconds: 5739820),
    artUri: "https://media.wnyc.org/i/1400/1400/l/80/1/ScienceFriday_WNYCStudios_1400.jpg",
  ),
  const MediaItem(
    id: "https://s3.amazonaws.com/scifri-segments/scifri201711241.mp3",
    album: "Science Friday",
    title: "From Cat Rheology To Operatic Incompetence",
    artist: "Science Friday and WNYC Studios",
    duration: Duration(milliseconds: 2856950),
    artUri: "https://media.wnyc.org/i/1400/1400/l/80/1/ScienceFriday_WNYCStudios_1400.jpg",
  ),
];
