import 'package:flutter/material.dart';
import 'package:hometoucher/RFB/RemoteScreenController.dart';
import 'package:hometoucher/Wigets/SelectHomeToucherServiceScreen.dart';
import 'package:hometoucher/main.dart';

class RemoteScreenSession extends StatelessWidget {
  final HomeToucherController homeToucherController;

  RemoteScreenSession({
    @required this.homeToucherController
  });

  @override
  Widget build(BuildContext context) {
    final remoteScreenController = homeToucherController.remoteScreenController;
    final mediaQueryData = MediaQuery.of(context);
    
    return 
      GestureDetector(
        child: CustomPaint(
          painter: _RemoteScreenPainter(
            controller: remoteScreenController,
            devicePixelRatio: mediaQueryData.devicePixelRatio
          ),
          size: mediaQueryData.size,
        ),
        onTapDown: (details) => remoteScreenController.onTapDown(details.localPosition * mediaQueryData.devicePixelRatio),
        onTapUp: (details) => remoteScreenController.onTapUp(details.localPosition * mediaQueryData.devicePixelRatio),
        onScaleEnd: (details) => Navigator.push(context, 
          MaterialPageRoute(
            builder: (_) => SelectHomeToucherManagerServiceScreen(
              model: homeToucherController.model,
              onHomeToucherManagerServiceSelected: () {
                Navigator.pop(context);
                homeToucherController.restartSession();
              }
            )
          ),
        )
      );
  }
}

class _RemoteScreenPainter extends CustomPainter {
  final RemoteScreenController controller;
  final double devicePixelRatio;

  _RemoteScreenPainter({
    this.controller,
    this.devicePixelRatio
  }): super(repaint: controller) {
    print('RemoteScreenPaiter created');
  }

  @override
  void paint(Canvas canvas, Size size) {
    //print('_RemoteScreenPainter size: $size');
    final image = controller.value;
    final paint = Paint();

    if(image != null) {
      canvas.scale(1/devicePixelRatio);
      canvas.drawImage(image, Offset.zero, paint);
    }
  }

  @override
  bool shouldRepaint(_RemoteScreenPainter oldDelegate) {
    print("shouldRepaint");
    return false;
  }
}
