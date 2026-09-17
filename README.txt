A510MiniBridge v0.1

Mục tiêu:
- Không sửa stream/video.
- Inject chỉ vào com.apple.CarPlayApp.
- Dump scene/window và kiểm tra A510 SBApplication + các class CarBridge liên quan.
- Không gọi requestActivation/private setters ở v0.1 để tránh crash CarPlay trước khi biết object/signature thật.

Test:
1. Build/cài tweak, respring.
2. Trong CarBridge bỏ tick A510Player.
3. Kết nối CarPlay.
4. Mở A510Player trên iPhone một lần.
5. Trên iPhone lấy log:
   cat /var/mobile/A510MiniBridge.log
6. Gửi log lại.

Nếu v0.1 thấy được SBApplication/scene handle, v0.2 mới thêm activation + presentation host.
