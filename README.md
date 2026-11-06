Cài Theos trên Mac/Linux.
Nếu máy rootless (thư mục /var/jb), bỏ dấu # ở dòng THEOS_PACKAGE_SCHEME trong Makefile.
Trong thư mục này chạy make package rồi cài file .deb ra máy (Filza, dpkg -i, hoặc Sileo).
Respring.
Bật / tắt
Tắt: defaults write com.recordunhide enabled -bool false rồi respring.
Bật lại: defaults write com.recordunhide enabled -bool true rồi respring.
Nếu bàn phím vẫn bị che
Xem log của SpringBoard (ví dụ oslog hoặc Console trên Mac) và lọc theo
RecordUnhide. Mỗi lần tweak gỡ cờ sẽ có một dòng log:
Có log nhưng vẫn bị che: cờ nằm ở chỗ khác, gửi lại log để chỉnh hook.
Không có log: kSecureBits trong Tweak.x chưa khớp, thử giá trị khác.
Lưu ý
Khi tweak đang bật, mọi thứ quay hoặc phản chiếu màn hình của máy này (kể cả
app khác) đều thấy được bàn phím mật mã và các chấm khi bạn nhập. Chỉ bật lúc
quay, dùng mật mã tạm, và tắt đi sau đó.
