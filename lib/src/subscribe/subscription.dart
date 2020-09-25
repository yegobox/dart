import 'dart:async';

import 'package:pubnub/core.dart';

import 'manager.dart';
import 'envelope.dart';

final _logger = injectLogger('pubnub.subscription.subscription');

/// Represents a subscription to a set of channels and channel groups.
///
/// Immutable. Can be paused and resumed multiple times.
/// After [cancel] is called, the subscription cannot be used again.
class Subscription {
  final Manager _manager;
  final bool _withPresence;
  final Set<String> _channels;
  final Set<String> _channelGroups;

  /// Whether this subscription receives presence events.
  bool get withPresence => _withPresence;

  /// Set of channels that this subscription represents.
  Set<String> get channels => {..._channels ?? {}};

  /// Set of channel groups that this subscription represents.
  Set<String> get channelGroups => {..._channelGroups ?? {}};

  /// Whether this subscription has been cancelled.
  bool get isCancelled => _cancelCompleter.isCompleted;

  /// Whether this subscription is currently paused.
  bool get isPaused => _envelopeSubscription == null;

  /// Set of presence channels that are generated from set of channels
  Set<String> get presenceChannels =>
      _channels.map((channel) => '${channel}-pnpres');

  /// Set of presence channel groups that are generated from set of channel groups
  Set<String> get presenceChannelGroups =>
      _channelGroups.map((channelGroup) => '${channelGroup}-pnpres');

  /// Broadcast stream of messages in this subscription.
  Stream<Envelope> get messages =>
      _envelopesController.stream.where((envelope) =>
          channels.contains(envelope.channel) ||
          channels.contains(envelope.subscriptionPattern) ||
          channelGroups.contains(envelope.subscriptionPattern));

  /// Broadcast stream of presence events.
  ///
  /// Will only emit when [withPresence] is true.
  Stream<PresenceEvent> get presence => _envelopesController.stream
      .where((envelope) =>
          presenceChannels.contains(envelope.channel) ||
          presenceChannels.contains(envelope.subscriptionPattern) ||
          presenceChannelGroups.contains(envelope.subscriptionPattern))
      .map<PresenceEvent>((envelope) => PresenceEvent.fromEnvelope(envelope));

  final Completer<void> _cancelCompleter = Completer();

  final StreamController<Envelope> _envelopesController =
      StreamController.broadcast();

  StreamSubscription<Envelope> _envelopeSubscription;

  Subscription(
      this._manager, this._channels, this._channelGroups, this._withPresence);

  /// Resume currently paused subscription.
  ///
  /// If subscription is not paused, then this method is a no-op.
  void resume() {
    if (isCancelled) {
      _logger
          .warning('Tried resuming a subscription that is already cancelled.');
      return;
    }

    if (!isPaused) {
      _logger.silly('Resuming a subscription that is not paused is a no-op.');
      return;
    }

    _logger.verbose('Resuming subscription.');

    _envelopeSubscription = _manager.envelopes.where((envelope) {
      // If message was sent to one of our channels.
      if (_channels.contains(envelope.channel)) {
        return true;
      }

      // If message was sent to one of our channel patterns.
      if (_channels.contains(envelope.subscriptionPattern)) {
        return true;
      }

      // If message was sent to one of our channel groups.
      if (_channelGroups.contains(envelope.subscriptionPattern)) {
        return true;
      }

      // If presence is enabled...

      if (withPresence) {
        // ...and message was sent to one of our presence channels.
        if (presenceChannels.contains(envelope.channel)) {
          return true;
        }

        // ...and message was sent to one of our presence channel groups.
        if (presenceChannelGroups.contains(envelope.subscriptionPattern)) {
          return true;
        }
      }

      // Otherwise this is not our message.
      return false;
    }).listen((envelope) {
      _envelopesController.add(envelope);
    });
  }

  /// Pause subscription.
  ///
  /// Pausing subscription will prevent the [messages] and [presence] streams from emitting messages.
  /// Keep in mind that you may miss messages while subscription is paused.
  /// If subscription is currently paused, this method is a no-op.
  void pause() {
    if (isCancelled) {
      _logger
          .warning('Tried to pause a subscription that is already cancelled.');
      return;
    }

    if (isPaused) {
      _logger
          .silly('Pausing a subscription that is already paused is a no-op.');
      return;
    }

    _logger.info('Pausing subscription.');

    _envelopeSubscription.cancel();
    _envelopeSubscription = null;
  }

  /// Cancels the subscription.
  ///
  /// This disposes internal streams, so the subscription becomes unusable.
  Future<void> cancel() async {
    if (isCancelled) {
      _logger.warning(
          'Tried cancelling a subscription that is already cancelled.');
      return;
    }

    _logger.verbose('Subscription cancelled.');

    await _envelopeSubscription.cancel();
    await _envelopesController.close();

    _cancelCompleter.complete();
  }

  /// Alias for [cancel].
  Future<void> dispose() => cancel();

  /// Alias for [resume].
  void subscribe() => resume();

  /// Alias for [pause].
  void unsubscribe() => pause();
}