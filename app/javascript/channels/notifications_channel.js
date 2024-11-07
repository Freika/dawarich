import consumer from "./consumer"

consumer.subscriptions.create("NotificationsChannel", {
  connected() {
    // console.log("Connected to the notifications channel!");
  },

  disconnected() {
    // Called when the subscription has been terminated by the server
  },

  received(data) {
    // Called when there's incoming data on the websocket for this channel
  }
});
