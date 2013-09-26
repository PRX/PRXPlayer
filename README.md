## PRXPlayer

PRXPlayer currently depends on a modified Reachability.

#### How to use

PRXPlayer is a lightweight wrapper around AVPlayer. It's job is simply to provide a standard set of tools, for free, that most implementations of an media player would have anyway. This includes things like: retry logic, error handling, observing basic state changes, and monitoring playback. PRXPlayer provides an abstracted set of NSNotifications, which make it easy for your app to respond to nearly all relevant changes. More precise interaction with the AVPlayer and its items and assets can be achieved by implementing a PRXPlayerDelegate. Beyond that, you always have the ability to deal with the underlying AVPlayer instances directly, allowing for as much customization as you need.

### PRXPlayerItem

The `PRXPlayer` API expects objects that implement the `PRXPlayerItem` protocol. This protocol ensures that objects contain the most basic set of properties that are required for a consistent media player experience. Every `PRXPlayerItem` must provide an `AVAsset`, which is what actually gets loaded into the underlying `AVPlayer`, and implement the `isEqualToPlayerItem:` to the player can accurately determine when player items have changed.

In some cases, the `AVAsset` of a given object may change over time. For instance, an episode object may by default have an `AVURLAsset` corresponding to a file on a remote server, but then returns an `AVURLAsset` corresponding to a file in local storage after the episode has been downloaded. In cases such as this, `isEqualToPlayerItem:` should be able to distnguish between these various situations, and return `NO` when a `PRXPlayerItem` is compared to itself, but with differing `AVAssets`.

### PRXPlayer

There are two groups of methods that a `PRXPlayer` has to allow for controlling playback: indifferent and explicit. The indifferent methods are: `play`, `pause`, `toggle`, and `stop`. These control the player regardless of what is loaded into the player. The explict controls, `playPlayerItem:`, `loadPlayerItem:`, and `togglePlayerItem:` deal with specific media objects. If an explict control message is sent to a `PRXPlayer` and the given object is not the currently loaded object, the player will take steps to clear out any existing media object and load the new one. `loadPlayerItem:` will prepare a media object as much as possible, up until the point where it can begin playback (ie it will start to buffer), but will keep the player paused once it's ready.

### PRXPlayerDelegate

Work in progress…

## Responding to changes

One of the primary functions of `PRXPlayer` is to make responding to changes for an `AVPlayer` and the associated media very easy. One way this is accomplished is by posting several very general notifications as changes come about. In most cases, parts of an app (eg UI elements, persistance layers, etc) are not concerned with what changed or what caused the change, simply that the change occured.

A common example would be the player controls UI presented in a music app. The controller managing the UI does not necessarily care why the player became paused, simply that the player changed state, and that the UI should be updated.

`PRXPlayer` will post a `PRXPlayerChangeNotification` any time the state of the player, it's underlying `AVPlayer`, or an asset loaded into the `AVPlayer` changes. Observing this notification, using the `sharedPlayer` as the object, should cover all situations needed to keep a player UI in sync with the player.

Additionally the `PRXPlayerTimeIntervalNotification` and `PRXPlayerLongTimeIntervalNotification` will be posted at one and 10 second intervals respectively any time playback is occuring through the `PRXPlayer`. Time jumps will also cause these notifications to be posted. For general use, the object registered for these notifications should be the `sharedPlayer`.

In cases where the asset that is playing back is an `AVURLAsset`, two additional notifications will be posted. They are also `PRXPlayerTimeIntervalNotification` and `PRXPlayerLongTimeIntervalNotification` notifications, but the object is the `absoluteString` of the `URL` of the `AVURLAsset`.

`PRXPlayer` also allows for the enforcement of WWAN (eg 3G/4G cellular connection) policy, and will post a `PRXPlayerReachabilityPolicyPreventedPlayback` if playback fails due to network connectivity conditions.