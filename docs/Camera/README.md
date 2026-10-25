# 카메라는 어떻게 화면에 나올까?

카메라를 켜는 일을 **문지기, 카메라 기사, 화면 친구**가 나눠서 한다고 생각하면 쉽다.

1. **문지기**가 카메라를 써도 되는지 물어본다. 처음이면 iPhone이 허락을 요청한다.
2. 허락을 받으면 **카메라 기사**가 앞쪽 카메라를 켠다.
3. **화면 친구**가 카메라 영상을 보여준다. 세로에서는 화면 전체에, 가로에서는 정해진 네모 칸에 놓는다.
4. 휴대폰을 돌리면 영상도 똑바로 보이도록 돌린다. 카메라를 새로 만들지 않고 같은 프리뷰를 계속 쓴다.

```text
ExperimentSessionView
  → CameraPermssionFeature → CameraPermissionClient
  → ExperimentSessionFeature
  → CameraSessionClient → CameraSession
  → CameraPreviewConnector → CameraPreviewView
```

## 파일은 어디에 있나?

| 위치 | 하는 일 |
| --- | --- |
| `Packages/ResearchersModules/Sources/LabcordiOS/Camera/Permission/` | 권한 상태 확인, 권한 요청, 설정 앱 열기 |
| `Packages/ResearchersModules/Sources/LabcordiOS/Camera/Session/` | 앞쪽 카메라 실행, 프리뷰 표시와 회전 |
| `Researchers/Features/ExperimentSession/` | 권한과 카메라를 연결하고 화면에 프리뷰 배치 |

두 카메라 폴더는 파일을 찾기 쉽게 나눈 것이다. 둘 다 같은 Swift Package의 `LabcordiOS` 타깃에 들어간다.

## 지금 되는 일과 남은 일

- **되는 일:** 카메라 권한 요청, 앞쪽 카메라 프리뷰, 세로·가로 배치와 회전, 카메라 시작 실패 알림.
- **아직 안 되는 일:** 사진 저장, 영상 녹화, 제스처 인식. 화면의 촬영 버튼에는 아직 동작이 없다.
- **다음에 연결할 일:** 권한 거부 시 설정 버튼 표시, 설정에서 돌아온 뒤 권한 다시 확인, 화면을 떠나거나 앱이 뒤로 가면 카메라 끄기.

## 중복 코드 검수

- 카메라 세션과 프리뷰는 각각 하나를 재사용한다. 시작 요청이 다시 와도 실행 중인 세션은 다시 켜지 않는다.
- 권한 요청 전 확인과 카메라 시작 직전 확인은 목적이 다르다. 뒤의 확인은 허락 없이 카메라를 켜지 않도록 지키는 장치다.
- 세로·가로 화면의 음성·사진·영상 버튼은 비슷한 내용이 반복된다. 모양이 달라 지금은 따로 두고, 실제 촬영 기능을 연결할 때 공통 액션을 쓰는 편이 좋다.
- `CameraPermssionFeature`의 이름에는 `Permission` 오타가 있다. 이름을 바꿀 때 참조하는 곳도 함께 고쳐야 한다.
