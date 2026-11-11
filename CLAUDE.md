# CLAUDE.md

공통 규칙(한국어 보고, 추천과 이유, 모델 분담, git 자동, 상태 셋, 세션 마무리)은 전체 지침 `~/.claude/CLAUDE.md`에 있다. 여기에는 이 프로젝트만의 것을 쓴다.

## 프로젝트

potatus hub는 RAM·CPU·GPU·디스크 사용률을 떠 있는 모듈 창과 메뉴바에 보여 주는 개인용 시스템 모니터다. 맥 앱(Swift, Apple Silicon)과 Windows 11 앱(C# WPF)이 한 저장소에 있다. 저장소 `bmminky/potatus-hub`는 **공개**다.

- **기능을 추가하거나 고치기 전에 `docs/ARCHITECTURE.md`를 먼저 읽는다.** 구조도, 파일별 맡은 일, "무엇을 고칠 때 어디를 여나" 표, 지켜야 할 약속이 있다. 그 표에서 고른 파일만 연다.
- 구조가 바뀌면(파일을 만들거나 옮기거나, 부품끼리 쓰는 방향이 바뀌면) 같은 커밋에서 `docs/ARCHITECTURE.md`도 고친다.
- 새 세션은 `docs/HANDOFF.md`(맨 위 상태표, 이어서 할 일)부터 읽는다.

## 빌드·시험

```bash
swift build
swift test
./Scripts/build-app.sh          # .build/potatus hub.app 을 만든다
```

- Claude 세션에서는 `swift build`·`swift test`·`build-app.sh`가 샌드박스 안에서 막힌다. 샌드박스 밖에서 실행한다.
- 설치는 `.build/potatus hub.app`을 `/Applications/potatus hub.app`으로 바꿔 넣는 것이다. 실행 중인 앱은 먼저 끈다.
- "화면이 바뀐 변경"은 모듈 창의 모양·움직임, 메뉴바 표시, 우클릭 메뉴를 말한다. 👀 확인 대기 때는 설치하고 실행해 둔다.
- 버전은 `Scripts/build-app.sh`의 `VERSION`과 `BUILD_NUMBER`다.
- Windows 앱은 이 맥에서 빌드하지 못한다. Windows 쪽을 고치면 "Windows에서는 빌드·확인 못 함"이라고 보고에 적는다.

## 구조

`docs/ARCHITECTURE.md`가 기준이다. 요약:

- `Sources/PotatusHub/App/` 시작과 연결, 설정 저장
- `Sources/PotatusHub/Metrics/` 측정
- `Sources/PotatusHub/Layout/` 배치 계산(화면을 모르는 순수 계산)
- `Sources/PotatusHub/Panels/` 모듈 창
- `Sources/PotatusHub/MenuBar/` 메뉴바 아이콘과 메뉴
- `windows/PotatusHub/` Windows 앱

## 열지 않는 것 (토큰 절약)

- `.build/`, `windows/**/bin/`, `windows/**/obj/`, `publish/`
- `Screenshots/`, `Resources/`의 그림 파일
- 맥만 고칠 때는 `windows/`를 열지 않는다.
