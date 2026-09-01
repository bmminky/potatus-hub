# potatus hub — Windows handoff

이 문서는 Windows 11 환경에서 `potatus hub` 개발과 배포를 이어가기 위한 현재 기준 문서입니다.

## 1. 시작하기

공개 저장소:

```powershell
git clone https://github.com/bmminky/potatus-hub.git
cd potatus-hub
```

필요한 환경:

- Windows 11 x64
- .NET 8 SDK
- Git
- 선택 사항: Visual Studio 2022의 **.NET desktop development** 워크로드
- 선택 사항: GitHub CLI (`gh`) — 릴리즈 업로드에 사용

Windows용 프로젝트는 `windows/PotatusHub/PotatusHub.csproj`입니다. macOS 소스인 `Sources/`, `Scripts/build-app.sh`, `Resources/`는 Windows 기능 작업 중 변경하지 않습니다. 공통 문서나 버전을 갱신해야 할 때만 별도로 수정합니다.

## 2. 바로 실행하기

개발 빌드:

```powershell
dotnet restore windows/PotatusHub/PotatusHub.csproj
dotnet build windows/PotatusHub/PotatusHub.csproj -c Debug
dotnet run --project windows/PotatusHub/PotatusHub.csproj
```

실행 후 창이 아니라 Windows 알림 영역(시스템 트레이)의 `potatus hub` 아이콘을 찾습니다.

- 왼쪽 클릭: 모든 모듈 숨기기 / 다시 표시
- 오른쪽 클릭: 모듈 표시, 새로고침, 숨기기, 정렬, 분리, 항상 위, 자동 실행, 언어, About, 종료

## 3. 현재 Windows 기능

- RAM, CPU, GPU 사용률 표시
- RAM·CPU·GPU 모듈 개별 표시 / 숨김
- 모듈 드래그 시 가로·세로·ㄴ자 형태로 결합
- 묶인 모듈을 길게 눌러 선택한 모듈만 분리
- 묶음 모듈 더블 클릭 시 가로 / 세로 전환
- 시스템 트레이 좌클릭으로 전체 숨김 / 표시
- 우클릭 메뉴: 새로고침, 숨기기, 정렬, 분리, 항상 위, 로그인 시 실행, 언어, About, 종료
- 한국어, English, 日本語, 中文 및 시스템 언어 따름
- 모듈 위치·표시 항목·언어·항상 위 상태 저장

## 4. 주요 파일

| 경로 | 역할 |
| --- | --- |
| `windows/PotatusHub/App.xaml.cs` | 앱 시작, 트레이, 메뉴, 모듈 결합·분리·정렬·저장 |
| `windows/PotatusHub/ModulePanel.xaml` | 투명 WPF 창과 그림자 표면 |
| `windows/PotatusHub/ModulePanel.xaml.cs` | 모듈 UI, 드래그, 길게 누르기, 애니메이션 |
| `windows/PotatusHub/ModuleLayout.cs` | 가로·세로·ㄴ자 레이아웃과 결합 규칙 |
| `windows/PotatusHub/SystemMonitor.cs` | RAM·CPU·GPU 측정 |
| `windows/PotatusHub/AppSettings.cs` | 표시 상태와 위치 저장 |
| `windows/PotatusHub/Localization.cs` | 4개 언어 메뉴 문자열 |
| `windows/PotatusHub/LaunchAtLogin.cs` | 로그인 시 실행 레지스트리 등록 |
| `windows/PotatusHub/Resources/AppIcon.ico` | Windows 실행 파일·트레이 아이콘 |
| `windows/build.ps1` | self-contained ZIP 및 SHA-256 생성 |
| `.github/workflows/windows-build.yml` | GitHub Actions Windows 빌드 / 아티팩트 |

## 5. 시스템 데이터 방식

- **RAM**: `GlobalMemoryStatusEx`
- **CPU**: `GetSystemTimes`의 두 샘플 간 차이
- **GPU**: Windows 성능 카운터 `GPU Engine / Utilization Percentage`

GPU는 엔진 인스턴스를 물리 GPU·엔진별로 합산한 뒤 가장 큰 값을 표시합니다. 성능 카운터를 제공하지 않는 PC나 드라이버에서는 `—`가 정상이며, 임의의 수치를 표시하면 안 됩니다.

설정 파일:

```text
%LOCALAPPDATA%\potatus hub\settings.json
```

자동 실행 레지스트리 위치:

```text
HKCU\Software\Microsoft\Windows\CurrentVersion\Run
```

## 6. Windows 배포 빌드

PowerShell에서 저장소 루트로 이동한 뒤 실행합니다.

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\windows\build.ps1
```

생성 결과:

```text
publish\win-x64\potatus hub.exe
potatus-hub-<version>-windows-x64.zip
potatus-hub-<version>-windows-x64.sha256
```

배포 전 확인:

1. `publish\win-x64\potatus hub.exe`를 실제 실행한다.
2. 트레이 아이콘, 좌·우 클릭, 언어 메뉴, 모듈 표시/숨김을 확인한다.
3. RAM·CPU 값이 갱신되는지 확인한다.
4. GPU가 지원 PC에서 갱신되는지 확인하고, 지원하지 않는 경우 `—`로 안전하게 보이는지 확인한다.
5. ZIP의 SHA-256을 생성된 `.sha256` 파일과 대조한다.

## 7. 버전과 릴리즈 규칙

현재 기준:

- macOS 최신 패치 릴리즈: `v0.3.1`
- Windows 배포본: `v0.3.0` 릴리즈의 `potatus-hub-0.3.0-windows-x64.zip`
- Windows 프로젝트와 `windows/build.ps1`은 현재 `0.3.0`을 사용

다음 Windows 릴리즈는 이미 사용된 버전을 덮어쓰지 말고 새 버전으로 올립니다. 예: `0.3.2`.

공통 릴리즈 버전을 올릴 때 아래 파일의 번호를 함께 맞춥니다.

```text
Scripts/build-app.sh
windows/PotatusHub/PotatusHub.csproj
windows/build.ps1
.github/workflows/windows-build.yml
README.md
```

Windows 전용 변경이라도 README의 다운로드 표와 체크섬이 실제 업로드 파일과 맞는지 확인합니다.

GitHub 릴리즈 예시:

```powershell
git switch -c windows/<short-description>
# 수정, 테스트, windows/build.ps1 실행
git add windows .github README.md
git commit -m "fix: <short description>"
git push -u origin HEAD

# main에 반영된 뒤에만 실행
git tag -a v0.3.2 -m "potatus hub 0.3.2"
git push origin main v0.3.2
gh release create v0.3.2 `
  .\potatus-hub-0.3.2-windows-x64.zip `
  .\potatus-hub-0.3.2-windows-x64.sha256 `
  --title "potatus hub 0.3.2"
```

GitHub Actions는 Windows 빌드 아티팩트를 만들지만 GitHub Release를 자동 생성하지는 않습니다. 릴리즈 ZIP과 체크섬 업로드는 위 절차처럼 별도로 수행합니다.

## 8. 작업 경계와 주의 사항

- macOS 앱의 SwiftUI/AppKit 코드는 Windows에서 빌드·수정 대상이 아닙니다.
- 아이콘을 바꿀 때는 Windows의 `AppIcon.ico`와 macOS의 PNG/ICNS를 각각 관리합니다.
- Windows `About`은 현재 기본 MessageBox입니다. macOS의 표준 About 패널과 같은 형태로 바꾸려면 WPF 전용 About 창을 새로 설계해야 합니다.
- 현재 Windows 빌드는 self-contained이지만 서명되지 않았습니다. SmartScreen 경고는 첫 실행 시 나타날 수 있습니다.
- GitHub에 공개하기 전 실제 Windows 11 환경에서 ZIP을 풀어 실행하는 검증을 우선합니다.

## 9. Windows Codex에 전달할 시작 문장

아래 문장을 새 작업에 붙여 넣으면 됩니다.

```text
Read POTATUS_HUB_WINDOWS_HANDOFF.md first. Continue work only in the Windows project under windows/. Preserve the macOS Swift project unless a shared release/document update is explicitly needed. Build and run the WPF app on this Windows machine before claiming a UI or release change is complete.
```
