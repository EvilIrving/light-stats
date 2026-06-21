# Light Stats

Light Stats는 "지금 내 Mac이 부하를 받고 있는지"를 보여주는 네이티브 macOS 메뉴 막대 시스템 모니터입니다. 사용량이 얼마나 찼는지가 아니라 응답성 압박에 초점을 둡니다. 0-100 건강도와 CPU, GPU, 메모리 압박 등 실시간 신호가 메뉴 막대에 상주하며, 팝오버를 열면 전체 그림(디스크 및 디스크 I/O, 네트워크, 프록시 및 출구 노드 상태, 배터리, 온도, 팬, 상위 프로세스, AI CLI 사용량)을 확인할 수 있습니다.

[English](README.md) · [简体中文](README.zh.md) · [日本語](README.ja.md) · **한국어**

---

https://github.com/user-attachments/assets/f167325d-e972-42fe-a54f-17a8a7a40834

---

## 스크린샷

| 개요 | 정리 |
|------|------|
| <img src="docs/screenshots/popover-overview.png" width="320" alt="개요 패널" /> | <img src="docs/screenshots/popover-cleanup.png" width="320" alt="정리 패널" /> |

---

## 개요

Light Stats는 Mac의 실시간 압박 신호를 메뉴 막대에 상시 표시하고, 더 자세한 정보가 필요할 때 떠 있는 패널을 엽니다. 활성 상태 보기를 계속 열어두지 않고 빠르게 상태를 확인하려는 사용자와, 네이티브 SwiftUI/AppKit 메뉴 막대 구현을 참고하려는 개발자를 위해 설계되었습니다.

일상적인 샘플링에는 macOS 네이티브 API를 사용하고, 서드파티 런타임 의존성이 없으며, 네트워크를 사용하는 진단 기능은 기본적으로 꺼져 있습니다.

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

### 메모리 정리

- 메모리 압박 개요 및 스왑 경고
- 메모리 사용량 기준으로 정렬된 앱 목록
- 일반 종료 및 확인 후 강제 종료
- 하위 프로세스 세부 정보 펼치기

### 창 제어

- 디자이너가 제공한 아이콘이 포함된 선택적 메뉴 막대 창 제어 메뉴
- 왼쪽, 오른쪽, 위쪽, 아래쪽 절반 배치에만 단축키를 두어 자주 쓰는 작업을 우선
- 모서리, 1/3 배치, 디스플레이 이동, 최대화, 가운데 배치, 복원, 최소화를 메뉴에서 실행
- 제목 표시줄 트랙패드 제스처로 빠르게 스냅하고, 미리보기와 햅틱 피드백 제공
- 창 제어, 전역 단축키, 제목 표시줄 제스처에는 손쉬운 사용 권한이 필요

### 스크롤 방향 제어

- 수직 및 수평 스크롤 방향 반전
- 스크롤 감도를 조정하는 단계 배율
- 관련 기능이 켜져 있을 때만 이벤트 tap 실행

### 청소 모드

- 키보드 청소를 위해 60초 동안 키보드 입력 잠금
- 전체 화면 반투명 오버레이와 카운트다운
- 마우스로만 종료할 수 있는 버튼, 키보드 입력은 억제
- CGEventTap을 사용하며 손쉬운 사용 권한이 필요

### 자동 업데이트

- GitHub Releases에서 새 버전 확인
- DMG 다운로드 후 codesign 서명, 공증, Team ID 검증
- 앱 종료 후 별도 스크립트로 실행 중인 app bundle 교체
- 다운로드 및 설치 중 가벼운 진행률 창 표시

### 네트워크 및 프록시

Light Stats는 환경 변수, 시스템 프록시 설정, 활성 터널 인터페이스에서 로컬 프록시 구성을 감지하며, 이 과정에서 외부 요청을 보내지 않습니다.

공개 출구 노드 감지는 선택 사항입니다. 켜면 선택한 geo-IP 공급자에 공개 IP, 위치, ASN, ISP를 조회하고 결과를 캐시하여 반복 요청을 피합니다.

### AI 구독 사용량

켜면 Light Stats는 Claude Code, Codex, Gemini CLI가 로컬에 저장한 인증 정보를 읽어 현재 구독 사용률을 개요 패널에 표시합니다. AI 모니터링은 기본적으로 꺼져 있으며, 인증 정보는 각 공급자 자체의 사용량 엔드포인트 외에는 어디에도 전송되지 않습니다.

### 건강도 점수

건강도 점수는 CPU, 메모리 압박과 스왑, 부하 평균, 온도, GPU, 전원 상태를 0-100점으로 요약합니다. 디스크 용량처럼 천천히 변하는 숫자보다 지금 Mac이 느려질 수 있는 실시간 압박 신호에 집중합니다. 노트북에서는 배터리 상태를, 데스크톱에서는 디스크 I/O 압박을 전원 항목으로 사용합니다. 누락되거나 꺼진 항목의 가중치는 자동으로 재조정됩니다.

---

## 개인정보 보호

Light Stats에는 원격 텔레메트리가 없습니다. 로컬 시스템 지표, 로컬 프록시 감지, 프로세스 목록, 스크롤 동작, 창 제어는 Mac 안에 머뭅니다.

출구 노드 감지는 기본적으로 꺼져 있습니다. 켜면 앱이 선택한 geo-IP 공급자에 요청을 보내 현재 공개 IP와 네트워크 소유자를 식별합니다. 결과는 60초 동안 캐시되며, 실패 시 조용히 폴백합니다.

AI 사용량 모니터링은 기본적으로 꺼져 있습니다. 켜면 요청은 각 공급자 자체의 사용량 엔드포인트로만 전송되며, 각 CLI가 이미 로컬에 저장한 인증 정보를 사용합니다.

업데이트 확인은 GitHub Releases에 연결합니다.

---

## 설정

- 메뉴 막대 항목 표시 여부
- 새로 고침 속도: 낮음 (5s), 중간 (2s), 높음 (1s)
- 온도 단위: 섭씨 또는 화씨
- 네트워크 속도 단위: 자동, KB/s, MB/s
- 출구 노드 감지 및 공급자 선택
- Claude Code, Codex, Gemini AI 모니터링 토글
- 수직 스크롤 반전, 수평 스크롤 반전, 단계 배율
- 창 단축키 및 제목 표시줄 제스처
- 건강도 점수 항목 토글
- 언어: 简体中文, English, 日本語, 한국어, 시스템 언어

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

기본 XCTest는 `LightStatsTests/LightStatsSmokeTests.swift`에 있습니다.

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

- `Light Stats/Models/`: 지표 데이터 구조, 건강도, 릴리스 정보
- `Light Stats/Services/`: 시스템 수집, 점수 계산, 업데이트, 스크롤, 창 제어, 키보드 잠금, AI 사용량
- `Light Stats/ViewModels/`: 앱 상태, 샘플링, 설정, 청소 모드, 업데이트 조율
- `Light Stats/Views/StatusBar/`: 메뉴 막대 렌더링
- `Light Stats/Views/Popover/`: 떠 있는 패널 UI 및 재사용 컴포넌트
- `Light Stats/Views/Settings/`: 설정 UI
- `Light Stats/Views/About/`: 정보 창
- `Light Stats/Views/CleaningMode/`: 청소 모드 오버레이
- `Light Stats/Views/Update/`: 업데이트 진행 창
- `Light Stats/Resources/`: 현지화 문자열 및 창 제어 아이콘
- `LightStatsTests/`: XCTest smoke tests
- `.github/workflows/`: 빌드, 배포, 릴리스 자동화

---

## 로드맵

- 더 자세한 네트워크 진단
- Intel, Apple Silicon, 노트북, 데스크톱 Mac 전반의 추가 검증
- 앱별 네트워크 사용량 추적
- 더 세분화된 정리 추천
- 창 제스처와 메뉴 막대 밀도 지속 조정
