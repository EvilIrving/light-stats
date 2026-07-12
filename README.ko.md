# Light Stats

Light Stats는 "지금 내 Mac이 부하를 받고 있는지"를 보여주는 네이티브 macOS 메뉴 막대 상태 계기입니다. 0-100 건강도와 실시간 신호를 표시하고, 필요할 때 AI CLI 사용량, 네트워크 출구, Finder 작업, 창 배치, 디스플레이 잠자기 방지를 추가할 수 있습니다. 팝오버는 네 가지 시각 테마(기본은 Default)를 지원하며, 설정 창은 시스템 흰색 도구 패널을 유지합니다.

[English](README.md) · [简体中文](README.zh.md) · [日本語](README.ja.md) · **한국어**

---

https://github.com/user-attachments/assets/f167325d-e972-42fe-a54f-17a8a7a40834

---

## 스크린샷

콜드 스타트 Default 테마 — 개요와 메모리:

| 개요 | 메모리 |
|------|--------|
| <img src="docs/screenshots/default/popover-overview.png" width="320" alt="개요 — Default" /> | <img src="docs/screenshots/default/popover-cleanup.png" width="320" alt="메모리 — Default" /> |

테마 (개요):

| Default | Bento Grid | Sun Gold | Ink Night |
|---------|------------|----------|-----------|
| <img src="docs/screenshots/default/popover-overview.png" width="200" alt="Default" /> | <img src="docs/screenshots/bento/popover-overview.png" width="200" alt="Bento" /> | <img src="docs/screenshots/sun-gold/popover-overview.png" width="200" alt="Sun Gold" /> | <img src="docs/screenshots/ink-night/popover-overview.png" width="200" alt="Ink Night" /> |

---

## 개요

Light Stats는 Mac의 실시간 압박 신호를 메뉴 막대에 상시 표시하고, 더 자세한 정보가 필요할 때 떠 있는 패널을 엽니다. 활성 상태 보기를 계속 열어두지 않고 상태를 확인하려는 고급 사용자와 AI 에이전트, 네트워크, Finder 작업 맥락을 가까이 두려는 개발자를 위한 앱입니다.

일상적인 샘플링에는 macOS 네이티브 API를 사용하고 서드파티 런타임 의존성이 없습니다. 모니터링은 읽기 전용 코어이며 네트워크 요청과 지속적인 시스템 작업은 **기본적으로 꺼져 있습니다**. 새로 설치한 직후에는 메뉴 막대 표시만 동작하고, 추가 아이콘, 손쉬운 사용 권한 요청, 이벤트 tap, 외부 요청이 없습니다.

---

## 기능

### 메뉴 막대

- 고정 너비 값으로 레이아웃 흔들림을 줄이는 컴팩트한 2줄 상태 표시
- Logo, CPU, GPU, 메모리, 디스크, 네트워크, 팬, 배터리, 건강도 선택 표시
- 업로드 및 다운로드 속도 표시
- 회전 아이콘 스타일의 팬 상태 표시
- 0-100 건강도 점수 선택 표시

### 개요 패널

- CPU, GPU, 메모리 압박, 스왑 활동, 부하 평균
- P/E 코어 사용률 차트와 상위 CPU 프로세스
- 지원되는 기기에서 배터리 상태, 충전량, 충전 횟수, 건강도, 전력, 온도
- 디스크 용량 및 집계 디스크 I/O 속도
- 네트워크 속도, 로컬 프록시 상태, 선택적 공개 출구 노드 정보
- 온도, 팬, 열 상태, 디스크 상태 표시줄
- 시스템 건강도 점수, 항목별 요약, 항목 토글
- AI 모니터링을 켜면 Claude Code, Codex, Gemini 구독 사용량 표시
- 주요 지표의 단기 스파크라인
- 지표 아이콘은 템플릿 색을 입힐 수 있는 SVG 아웃라인(CPU, GPU, 메모리, 디스크, 네트워크, 프록시, 온도, 프로세스)

### 외관

- 제품 표면(팝오버, 정보, Toast, 업데이트, 권한 안내)용 네 가지 테마:
  - **Default**(콜드 스타트 기본): 시스템 계기판 읽기(카드 프레임 없음. macOS 26+는 Liquid Glass, macOS 15는 일반 시스템 표면)
  - **Bento Grid**: 기존 카드 그리드 + 시스템 머티리얼
  - **Sun Gold**: 따뜻한 금빛 그레인 메시
  - **Ink Night**: 먹빛 그레인 메시와 차콜 표면
- Sun Gold / Ink Night는 공통 외관 조절: 그레인 on/off, 빛 움직임 5단계(정지, 완만, 자연, 부드러움, 활발)
- 설정 창은 시스템 흰색을 유지하고 표시 테마를 따르지 않아 차분한 도구 패널로 남습니다

### 메모리 정리

- 메모리 압박 개요 및 스왑 경고
- 메모리 사용량 기준으로 정렬된 앱 목록
- 일반 종료 및 확인 후 강제 종료
- 하위 프로세스 세부 정보 펼치기
- 레이아웃은 활성 테마를 따름(Bento는 카드, 나머지는 instrument 행)

### Finder 메뉴

- 기본적으로 꺼진 선택형 FinderSync 확장
- 경로나 파일 이름 복사, 선택한 터미널에서 열기, 숨김 상태 전환
- 문서, 웹, 데이터, 코드로 분류된 새 파일 템플릿
- 새 파일은 유형별 시작 이름 사용(예: `index`, `main`, `notes`). 일괄 Untitled 아님
- 즐겨찾기 디렉터리로 이동 또는 복사하고 설정한 앱으로 열기
- 현재 Finder 위치에서 cmux 새 창 또는 작업 공간 열기
- 설정에서 확장 등록 상태 확인 및 Finder 새로 고침

### 창 관리

- 단일 **"창 관리" 스위치**(기본 꺼짐)로 메뉴 막대 창 제어 아이콘, 전역 스냅 단축키, 제목 표시줄 제스처를 한 번에 함께 켭니다. 별도의 하위 토글은 없습니다
- 디자이너가 제공한 아이콘이 포함된 메뉴 막대 창 제어 메뉴
- 왼쪽, 오른쪽, 위쪽, 아래쪽 절반 배치에만 단축키를 두어 자주 쓰는 작업을 우선
- 모서리, 1/3 배치, 디스플레이 이동, 최대화, 가운데 배치, 복원, 최소화를 메뉴에서 실행
- 제목 표시줄 트랙패드 제스처로 빠르게 스냅하고, 미리보기와 햅틱 피드백 제공
- 스위치를 끄면 아이콘을 즉시 제거하고 모든 창 제어 이벤트 tap을 중지합니다. 손쉬운 사용 권한은 스위치를 켤 때만 요청됩니다

### 스크롤 방향 제어

- 수직 및 수평 스크롤 방향 반전
- 스크롤 감도를 조정하는 단계 배율
- 관련 기능이 켜져 있을 때만 이벤트 tap 실행

### 청소 모드

- 키보드 청소를 위해 60초 동안 키보드 입력 잠금
- 전체 화면 반투명 오버레이와 카운트다운
- 마우스로만 종료할 수 있는 버튼, 키보드 입력은 억제
- CGEventTap을 사용하며 손쉬운 사용 권한이 필요

### 잠자기 방지 및 로그인 시 실행

- 손쉬운 사용 권한 없이 디스플레이 잠자기 방지
- 끄거나 Light Stats를 종료하면 즉시 중지
- macOS 네이티브 로그인 항목 서비스로 로그인 시 실행 설정

### 업데이트

- 수동 확인과 선택형 자동 확인에서 GitHub Releases 사용. 자동 확인은 기본적으로 꺼짐
- 업데이트 채널: **Stable**(정식 릴리스만) 또는 **Beta**(`v1.9.0-beta.N` 같은 prerelease 포함)
- SemVer 2.0으로 프리릴리스 식별자를 올바르게 비교해 beta 증가와 정식 전환을 인식
- DMG 다운로드 후 codesign 서명, 공증, Team ID 검증
- 앱 종료 후 별도 스크립트로 실행 중인 app bundle 교체
- 다운로드 및 설치 중 가벼운 진행률 창 표시

### 진단 로그

- Unified Logging과 로컬 JSONL에 쓰는 구조화 진단 로그(원격 전송 없음)
- 3단계: 끔 / 오류만 / 전체(기본 전체). 약 5일 보관, 로테이션과 마스킹
- 설정에서 로컬 로그 폴더를 열 수 있음. 프로세스 신원, 네트워크 주소, 출구 노드 상세는 전체 형태로 쓰지 않음

### 네트워크 및 프록시

Light Stats는 환경 변수, 시스템 프록시 설정, 활성 터널 인터페이스에서 로컬 프록시 구성을 감지하며, 이 과정에서 외부 요청을 보내지 않습니다.

공개 출구 노드 감지는 선택 사항입니다. 켜면 선택한 geo-IP 공급자에 공개 IP, 위치, ASN, ISP를 조회하고 결과를 캐시하여 반복 요청을 피합니다.

### AI 구독 사용량

켜면 Light Stats는 Claude Code, Codex, Gemini CLI가 로컬에 저장한 인증 정보를 읽어 해당 공급자에서 현재 구독 사용률을 가져옵니다. AI 모니터링은 기본적으로 꺼져 있으며, 인증 정보는 다른 공급자나 Light Stats 개발자에게 전송되지 않습니다.

Claude Code와 Codex에는 별도의 사용량 창 유지 스위치가 있으며 둘 다 기본적으로 꺼져 있습니다. 롤링 창이 재설정된 뒤 임시 빈 디렉터리에서 해당 CLI를 통해 최소 프롬프트 `ok`를 보내고 일반 출력을 버린 다음 새 창을 확인합니다. Gemini에는 이 기능이 없습니다.

### 건강도 점수

건강도 점수는 CPU, 메모리 압박과 스왑, 부하 평균, 온도, GPU, 전원 상태를 0-100점으로 요약합니다. 디스크 용량처럼 천천히 변하는 숫자보다 지금 Mac이 느려질 수 있는 실시간 압박 신호에 집중합니다. 노트북에서는 배터리 상태를, 데스크톱에서는 디스크 I/O 압박을 전원 항목으로 사용합니다. 누락되거나 꺼진 항목의 가중치는 자동으로 재조정됩니다.

---

## 개인정보 보호

Light Stats에는 원격 텔레메트리가 없습니다. 로컬 시스템 지표, 로컬 프록시 감지, 프로세스 목록, 스크롤 동작, 창 제어는 Mac 안에 머뭅니다.

- 새로 설치한 앱은 외부 요청을 보내지 않습니다. 출구 노드 조회, AI 사용량 모니터링, Claude/Codex 창 유지, 자동 업데이트 확인은 모두 기본적으로 꺼져 있습니다. Beta 업데이트 채널도 기본 꺼짐입니다.
- 출구 노드 감지는 선택한 geo-IP 공급자에 공개 IP, 위치, ASN, ISP를 조회하고 결과를 60초 동안 캐시합니다.
- AI 모니터링은 켠 공급자 자체의 사용량 엔드포인트에만 연결하고 해당 CLI가 저장한 인증 정보를 사용합니다.
- 선택형 Claude/Codex 창 유지는 위에서 설명한 최소 프롬프트를 해당 공급자의 CLI로 보냅니다.
- 수동 업데이트 확인과 선택형 자동 확인은 GitHub Releases에 연결하며, 다운로드 후 서명, 공증, Team ID를 검증합니다.
- 진단 로그(기본 전체, 오류만/끔으로 변경 가능)는 디스크에만 남고 프라이버시 마스킹이 있으며 Light Stats 개발자에게 전송되지 않습니다.

분석, 충돌 보고, 광고, 계정 시스템, 개발자가 운영하는 텔레메트리 엔드포인트가 없습니다. 자세한 내용은 [개인정보 보호 정책](https://evilirving.github.io/light-stats/#privacy)을 확인하세요.

---

## 설치

[GitHub Releases](https://github.com/EvilIrving/light-stats/releases/latest)에서 최신 DMG를 내려받아 열고 Light Stats를 응용 프로그램 폴더로 드래그하세요. 릴리스 빌드는 서명 및 공증되어 있으며, 내장 업데이터도 교체 전에 codesign, 공증, Team ID를 검증합니다.

요구 사항: macOS 14 이상. Apple Silicon이 주요 대상입니다.

---

## 설정

- 시각 테마(Default / Bento / Sun Gold / Ink Night)와 Sun Gold/Ink Night 그레인·빛 움직임
- 메뉴 막대 항목 표시 여부
- 새로 고침 속도: 낮음 (5s), 중간 (2s), 높음 (1s)
- 온도 단위: 섭씨 또는 화씨
- 로그인 시 실행, 자동 업데이트 확인, Stable/Beta 채널, 디스플레이 잠자기 방지
- 진단 로그 수준(끔 / 오류 / 전체)과 로그 폴더 열기
- 출구 노드 감지 및 공급자 선택
- Claude Code, Codex, Gemini AI 모니터링과 Claude/Codex 개별 창 유지 스위치
- 수직 스크롤 반전, 수평 스크롤 반전, 단계 배율
- 창 관리(메뉴 막대 아이콘, 스냅 단축키, 제목 표시줄 제스처를 묶는 단일 토글)
- Finder 메뉴, 터미널 선택, cmux 작업, 즐겨찾기 디렉터리, 앱, 파일 템플릿
- 건강도 점수 항목 토글
- 언어: 简体中文, English, 日本語, 한국어, 시스템 언어

설정은 "일반", "모니터링", "추가 도구"로 나뉘며 사이드바 상태 점으로 현재 켜진 선택형 기능을 확인할 수 있습니다. 창은 시스템 흰색 고정 캔버스이며, 표시 테마는 팝오버 등 제품 표면에만 적용됩니다.

---

## 개발

자세한 내용은 [CONTRIBUTING.md](CONTRIBUTING.md)를 참고하세요.

### 요구 사항

- macOS 14+
- Xcode 16 이상 권장
- Swift 5.9+
- 로컬 lint에는 SwiftLint 필요 (`brew install swiftlint`)

### 빌드

```bash
# 최신 Debug app을 빌드하고 실행
./debug-run.sh

# 수동 Debug 빌드
xcodebuild -project "Light Stats.xcodeproj" \
  -scheme "Light Stats" \
  -configuration Debug \
  -derivedDataPath build/DerivedData build

# Release DMG
./build.sh
```

### 품질 확인

```bash
swiftlint lint --strict
./validate_localization.sh
```

GitHub Actions는 SwiftLint, 현지화 검증, Release 빌드, 산출물 업로드, 태그 서명/공증, GitHub Release 생성을 실행합니다.

### 테스트

XCTest 스위트는 `LightStatsTests/`에 있으며 Xcode 프로젝트에 연결되어 있습니다(공유
`Light Stats` 스킴의 `LightStatsTests` 유닛 테스트 타깃). CI와 아래 명령 모두 이를 실행합니다.
커버리지는 회귀가 잦은 순수 로직에 집중합니다: `HealthScoreService` 점수 곡선, "기본 꺼짐"
설정 계약, 그리고 세 가지 AI 사용량 JSON 파서(픽스처는 `LightStatsTests/Fixtures/`).

```bash
xcodebuild test \
  -project "Light Stats.xcodeproj" \
  -scheme "Light Stats" \
  -destination 'platform=macOS'
```

### 기술 스택

- 패널 및 설정에 SwiftUI
- 메뉴 막대 통합, 팝오버, 오버레이, 커스텀 뷰에 AppKit
- Combine 및 Swift Concurrency
- Mach API, IOKit, Accessibility, Core Graphics event tap, CFNetwork, Network, SMC, getifaddrs
- 서드파티 런타임 의존성 없음

### 아키텍처

앱은 모델, 서비스, 뷰 모델, 뷰 계층으로 분리되어 있습니다. `SystemMonitor`가 샘플링을 조율하여 UI에 스냅샷을 발행하고, 각 서비스가 해당 지표를 수집합니다.

캐시되거나 비동기적인 수집기(출구 노드 조회, AI 사용량 공급자 등)는 actor를 사용합니다. UI에 묶인 상태는 main actor에 둡니다. 빠른 syscall 헬퍼는 적절한 경우 동기로 유지합니다.

### 프로젝트 구조

- `Light Stats/Models/`: 지표 데이터 구조, 건강도, 릴리스 정보, `AppTheme`
- `Light Stats/Services/`: 시스템 수집, 점수 계산, 업데이트, 스크롤 반전, 창 스내핑, 단축키, 제목 표시줄 제스처, 키보드 잠금, AI 사용량, 진단 로그
- `Light Stats/ViewModels/`: 앱 상태, 샘플링, 설정, 청소 모드, 업데이트 조율
- `Light Stats/Views/StatusBar/`: 메뉴 막대 렌더링
- `Light Stats/Views/Popover/`: 떠 있는 패널 UI 및 재사용 컴포넌트
- `Light Stats/Views/Theme/`: 테마 토큰, 메시 배경, 그레인, 피커, 외관 프리셋
- `Light Stats/Views/Settings/`: 설정 UI(시스템 흰색 도구 패널)
- `Light Stats/Views/About/`: 정보 창
- `Light Stats/Views/CleaningMode/`: 청소 모드 오버레이
- `Light Stats/Views/Update/`: 업데이트 진행 창
- `Light Stats/Views/Permission/`: 테마형 손쉬운 사용 안내
- `Light Stats/Utilities/`: 포맷터, 지표 이력, `SVGIcon`
- `Light Stats/Resources/`: 현지화 문자열, 창 제어 아이콘, 지표 SVG
- `FinderMenu/` 및 `FinderMenuExtension/`: 공통 Finder 작업과 FinderSync 통합
- `LightStatsTests/`: XCTest(건강도, 기본값, AI 파서, PTY, 진단, SemVer, Finder 템플릿)
- `.github/workflows/`: 빌드, 배포, 릴리스 자동화

---

## 로드맵

- 더 자세한 네트워크 진단
- Intel, Apple Silicon, 노트북, 데스크톱 Mac 전반의 추가 검증
- 앱별 네트워크 사용량 추적
- 더 세분화된 정리 추천
- 테마, 창 제스처, 메뉴 막대 밀도 지속 조정
