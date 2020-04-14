# HomeToucher-Flutter
HomeToucher implemented in Flutter

HomeToucher is an application oriented VNC client. It is intended to act as a remote screen for a specific application which is running on a server.

I developed it in order to access my Home Automation system screens (the screens started their existance as a Windows-CE based system for which I have written a C++ firmware that presents a UI from an XML based language). Now I am running the same C++ code on a server, but instead of drawing to a physical screen, the UI is also accessible via VNC client (RFB protocol).

A regular VNC client is Ok, but not good enough. It has to be manually configured, and the server side has no way to adjust its screen size to the device screen size (VNC was designed to allow remote control of desktop computers). In addition if the server goes down, in most VNC clients you will have to manually reconnect.

HomeToucher is design to run unattended on devices such as tablets

You can find more about HomeToucher (especially if you would like to implement the server side in: https://yuvalrakavy.wixsite.com/hometoucher/technical-specs

The original implementation was written in Objective-C. When Swift became available, I have reimplemented it in Swift (https://github.com/yuvalrakavy/VillaRakavy-HomeToucher)

When Flutter came alone, I have decided that implementing this in Flutter is a great project and it will also provide with an Android version as a huge side benefit.

I found Flutter to be a really amazing tool with amazing performence.

 Enjoy,
 
  Yuval
  
