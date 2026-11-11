# Sắp xếp lại các file đang nằm phẳng trong lib\ vào đúng thư mục con.
# Chạy tại thư mục gốc dự án (nơi có pubspec.yaml):
#   powershell -ExecutionPolicy Bypass -File .\setup_structure.ps1
$map = @{
  'app_constants.dart'        = 'lib\core\constants'
  'app_theme.dart'            = 'lib\core\theme'
  'formatters.dart'           = 'lib\core\utils'
  'password_hasher.dart'      = 'lib\core\utils'
  'local_config_storage.dart' = 'lib\core\utils'
  'user_model.dart'           = 'lib\data\models'
  'booking_model.dart'        = 'lib\data\models'
  'service_model.dart'        = 'lib\data\models'
  'google_sheets_service.dart'= 'lib\data\services'
  'auth_provider.dart'        = 'lib\providers'
  'booking_provider.dart'     = 'lib\providers'
  'service_provider.dart'     = 'lib\providers'
  'user_provider.dart'        = 'lib\providers'
  'add_booking_screen.dart'   = 'lib\presentation\screens\booking'
}
foreach ($name in $map.Keys) {
  $src = Join-Path 'lib' $name
  if (Test-Path $src) {
    New-Item -ItemType Directory -Force -Path $map[$name] | Out-Null
    Move-Item $src (Join-Path $map[$name] $name) -Force
    Write-Host "OK   $name -> $($map[$name])"
  } else {
    Write-Host "THIEU $name (khong thay trong lib\)" -ForegroundColor Yellow
  }
}
# File test mẫu của `flutter create` tham chiếu class MyApp không tồn tại
if (Test-Path 'test\widget_test.dart') { Remove-Item 'test\widget_test.dart'; Write-Host 'Da xoa test\widget_test.dart' }
