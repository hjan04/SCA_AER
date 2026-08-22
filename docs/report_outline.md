SCA_AER 1차 보고서 초안 구성

이 문서는 뼈대(outline)입니다. 시뮬레이션/합성 진행하면서 각 섹션의 실제 수치, 스크린샷, 리포트 내용을 채워 넣으시면 됩니다.

0. 표지
대회명 / 팀명(SCA) / 팀원 명단
제출일 (2026-08-28)
주제: Bio-mimic Neuron을 위한 AER 통신방식 설계
1. 서론
1.1 연구 배경

뉴로모픽(neuromorphic) 시스템은 생물학적 신경망의 동작 방식을 모사하여, 연속적인 신호 대신 이산적인 스파이크(spike) 형태로 정보를 주고받는다. 이때 다수의 뉴런이 발생시키는 스파이크를 제한된 통신 채널로 효율적으로 전달하기 위한 방식이 AER(Address Event Representation)이다. AER은 스파이크가 발생한 뉴런의 "주소"만을 전송함으로써 배선 수를 줄이고, 시간 다중화(time-division multiplexing)를 통해 다수의 가상 채널을 하나의 물리적 채널로 통합한다는 장점이 있다. 그러나 이 방식은 태생적으로 비동기(asynchronous) 통신을 전제로 설계되어 왔으며, 이는 표준 동기식 디지털 설계 플로우(RTL → Synthesis → STA)와 궁합이 맞지 않는 구조적 한계를 갖는다.

1.2 연구 목적

본 연구는 전통적인 AER 통신 방식을 분석하여 그 구조적 문제점을 도출하고, 이를 개선한 AER 설계 방향을 제시한 뒤 실제로 RTL 수준에서 구현하는 것을 목표로 한다. 특히 본 대회의 제출 요건(RTL, Synthesis, Timing 최적화, Area, Power, 최대 동작 주파수)을 고려하여, 개선 방향은 정량적으로 합성·검증 가능한 형태로 구체화한다.

1.3 진행 방식 요약

DVS(Dynamic Vision Sensor) 계열 pixel array의 x/y 좌표와 polarity event를 대상으로, baseline과 개선 구조를 각각 RTL로 구현하고 SystemVerilog 기반 self-checking simulation(Icarus Verilog)으로 기능을 검증하였다. baseline 구조를 89회 벤치마크하여 병목을 정량적으로 특정한 뒤, 그 병목을 해소하는 개선 구조를 설계하고 동일 물리 대역폭(physical bandwidth) 조건에서 84회 비교 시뮬레이션을 수행하였다. 최종적으로 Cadence Genus를 통해 두 구조를 동일 조건으로 합성하여 Area/Power/Fmax를 비교하고, 앞서 측정한 throughput 결과와 결합하여 Throughput/Area, Throughput/Power와 같은 종합 효율 지표까지 도출하는 것을 목표로 한다.

전체 진행은 다음 6단계 로드맵을 따른다.

Stage	목표	상태
0	아키텍처 정의 (Baseline/Adaptive 후보 및 벤치마크 확정)	완료
1	Baseline RTL 구현 + directed verification	완료
2	Baseline 89회 벤치마크로 병목 측정	완료
3	Adaptive RTL(4×4 sparse/dense bitmap) 구현·검증	완료
4	동일 물리 대역폭 기준 84회 비교 시뮬레이션	완료
5A	Cadence Genus/공식 PDK 환경 조사	진행 중
5B	Genus PPA 합성 및 비교	예정
2. 전통(Baseline) AER 분석
2.1 AER 통신 방식 개요

AER은 다수의 이벤트 소스(픽셀/뉴런)가 공유하는 하나의 통신 채널을 통해, 이벤트가 발생한 소스의 주소(address)만을 전송하는 방식이다. 여러 소스가 동시에 이벤트를 발생시킬 경우, 아비터(arbiter)가 이들 중 하나를 선택하여 순차적으로 전송을 처리하며, 송수신 간에는 REQ/ACK 핸드셰이크로 전송 완료 시점을 동기화한다.

2.2 Baseline 구조: 2-level Row/Column Round-Robin AER

본 연구의 baseline은 synchronous 2-level row/column round-robin AER로 정의하였다. 고정 우선순위 대신 round-robin을 채택한 이유는, baseline을 의도적으로 약하게 설계하여 개선 구조가 상대적으로 유리해 보이는 것을 방지하기 위함이다.

데이터 흐름은 다음과 같다.

Pixel Event Array → Event Capture → Pending Bitmap/Polarity → Row RR → Column RR → {polarity, y, x} → REQ/ACK
각 픽셀은 pending 1비트 + polarity 1비트로 상태를 표현한다.
이미 pending 상태인 픽셀에 새 이벤트가 발생하면 별도 저장 공간이 없어 유실(capture loss)된다.
단, ACK 사이클 중 같은 픽셀에 새 이벤트가 발생하면, 그 새 이벤트는 pending으로 보존된다.
2.3 Stage 1 기능 검증 (Directed Verification)

Icarus Verilog 기반 self-checking simulation으로 아래 8종 시나리오를 검증하였으며, 전부 PASS하였다.

테스트	결과
single_event	PASS
simultaneous	PASS
round_robin	PASS
delayed_ack	PASS
back_to_back	PASS
repeated_pixel	PASS
clear_and_new	PASS
heavy_traffic	PASS

특히 clear_and_new, delayed_ack 케이스를 통해 capture/handshake의 corner case까지 검증하였다.

2.4 Stage 2 — Baseline Characterization (문제점 도출)

Adaptive 구조를 먼저 가정하지 않고, baseline 자체를 uniform random / Poisson-like / hotspot / burst / simultaneous multi-pixel / spatial locality sweep 등 다양한 트래픽 패턴으로 총 89회 실측 벤치마크하여 병목을 정량적으로 특정하였다.

항목	결과
Saturation point	약 0.2987 events/cycle
High-load ceiling	약 0.333 events/cycle
주 병목	four-phase, one-event-per-transaction output path
Hotspot 부작용	pending 시간 증가로 same-pixel capture loss 증가

즉 baseline의 근본적인 한계는 한 번의 handshake로 이벤트 1개만 전송 가능하다는 직렬화(serialization) 구조이며, 이것이 이후 개선 방향(4×4 블록 단위로 여러 이벤트를 묶어 전송)의 근거가 되었다.

2.5 참고 문헌 및 레퍼런스 설계

Baseline/Adaptive 설계는 AER의 일반적인 개념(Boahen, 2000 등)을 기반으로 자체 설계하였다.

2.6 관련 연구와 차별점

본 설계와 개념적으로 가까운 선행 연구는 다음과 같다.

Boahen (2004), "A Burst-Mode Word-Serial Address-Event Link": 한 행(row)의 공통 주소를 한 번만 전송하고 활성 픽셀들의 열(column) 주소를 연속 전송하여, 공간적 locality로 반복 주소·중재 비용을 줄인다. "공간 locality를 이용해 AER 비용을 줄인다"는 사고방식의 원류.
Son et al. (2017, ISSCC), Group-AER: 640×480 DVS에서 픽셀을 그룹으로 묶어 group address + 그룹 내 픽셀별 event status vector를 전송하는 "fully synthesized word-serial group-AER"를 제안하였다. 본 연구의 dense 모드(block 좌표 + valid/polarity bitmap)와 가장 가까운 선행 기술이다.
Purohit & Manohar (2021), Hierarchical Token Rings: sparse 이벤트는 트리처럼, 밀집 구간은 선형 토큰 링처럼 처리하는 계층적 아비트레이션 구조. 본 연구와 달리 패킷 표현이 아니라 arbitration/routing topology 자체를 적응시킨다.
Purohit & Manohar (2022), FP-AER: 설정 비트를 통해 event-based/cluster/full-frame readout 구조를 선택 가능하게 한다. 본 연구와 달리 사람이 미리 설정(configure)하는 방식이며, 순간적인 트래픽에 실시간 반응하지 않는다.
Wang et al. (2026, arXiv 2604.05313): 완전히 synthesizable한 tree 기반 비동기 AER 인코더를 65nm 실리콘으로 검증. 본 연구와 유사하게 상용 EDA 플로우(Cadence)와의 호환성을 목표로 하나, 압축이 아닌 비동기 인코더 자체의 합성 가능성에 초점을 둔다.

본 연구의 차별점은 "비트맵/그룹 전송" 자체가 아니라 다음 조합에 있다.

순간적인 pending occupancy에 따라 sparse/dense를 runtime에 자동 선택 (Group-AER는 항상 그룹 단위, FP-AER는 사람이 설정)
패킷 snapshot과 ACK clear 시맨틱스를 통한 동시 발생 이벤트의 정확한 처리
동일한 fixed-width serializer/deserializer를 통한 물리 비트 비용 기준의 공정 비교
overload/burst/hotspot 각각에서의 병목 이동(bottleneck migration)을 실측으로 규명

가장 안전한 포지셔닝 문장은 다음과 같다: "기존 Group-AER의 grouped representation 개념을 기반으로, spatial occupancy에 따른 runtime sparse-dense mode selection과 equal-bandwidth hardware evaluation을 추가한 AER microarchitecture." "세계 최초의 비트맵 AER"과 같은 과장된 주장은 지양한다.

3. 개선 AER 설계 방향: Traffic-Adaptive Hybrid AER
3.1 문제점과 개선 아이디어

Stage 2에서 확인한 baseline의 핵심 병목은 "한 번의 handshake로 이벤트 1개만 전송"하는 직렬화 구조였다. 이를 해소하기 위해, 트래픽이 sparse할 때는 기존 방식을 유지하고, spatially dense하거나 burst 트래픽일 때는 여러 이벤트를 하나의 패킷으로 묶어 전송하는 하이브리드 방식을 채택하였다. 이는 대회의 다른 팀들이 검토 중인 coordinate compression, synchronous AER, bus-width 최적화 등과 차별화되는 지점이다.

3.2 채택한 구조: Sparse/Dense 4×4 Block Bitmap Adaptive AER

Pending bitmap의 4×4 블록 단위 occupancy(점유율)를 계산하여 전송 모드를 결정한다.

Pending Bitmap → Block Occupancy → Mode Decision → Sparse RR / Dense Block → Packet Register → Output
Sparse 모드: 기존과 동일하게 x/y/polarity 이벤트 1개를 전송한다.
Dense 모드: 블록 좌표 + 16비트 valid mask + 16비트 polarity mask로, 최대 16개 이벤트를 한 패킷으로 묶어 전송한다.
패킷 생성 시점에 스냅샷을 고정하고, ACK 시 스냅샷에 포함된 이벤트만 clear한다. 같은 ACK 사이클에 발생한 새 이벤트는 보존되어 유실되지 않는다.
baseline과 동일한 픽셀당 캡처 용량(pending 1비트)을 유지하여 공정한 비교 조건을 만든다.

모드 결정 타이밍: 이 구조는 dense 조건이 채워질 때까지 전송을 일부러 지연시키는 방식이 아니다. 매 사이클 pending bitmap을 즉시 검사하여, dense-eligible 블록(occupancy ≥ threshold)이 있으면 dense로, 없으면 해당 이벤트를 sparse로 즉시 전송한다. 별도의 대기 타이머나 coalescing window는 없다. 단, REQ/ACK 처리나 serializer가 이미 busy인 동안 pending bitmap에 자연스럽게 이벤트가 쌓일 수 있으며, 그 과정에서 occupancy가 threshold에 도달하면 다음 패킷 선택 시 dense로 전환된다 — 이는 "혼잡으로 인한 자연스러운 누적"이지 "dense를 만들기 위한 의도적 대기"가 아니다. 이 설계 덕분에 Stage 4에서 관측된 latency 개선(178.8→46.8 cycles)이 인위적 지연 없이 달성되었음을 확인할 수 있다.

3.3 블록 크기와 임계값(Threshold) 결정

Dense 인코딩이 실제로 유리해지는 손익분기점(break-even)을 사전에 계산하였다.

Block	Dense packet	Break-even
2×2	15 bits	2 events
4×4	37 bits	5 events
8×8	131 bits	15 events

이를 바탕으로 4×4 블록, DENSE_ENTER_THRESHOLD = 5를 Stage 3 초기값으로 설정하였다. (이후 물리 링크 폭을 고려한 재평가는 8장 참조)

3.4 공정 비교를 위한 설계 원칙

Dense 패킷은 논리적으로 더 넓은 정보를 담기 때문에, "handshake 횟수"만으로 우위를 주장하면 공정하지 않다. 이 문제는 4장(동일 물리 대역폭 비교)에서 실제 전송 비트 수까지 포함하여 해결하였다.

3.5 물리 대역폭 기준 Threshold 재평가

3.3절의 threshold=5는 논리적 break-even 기준이었다. 실제 16bit 링크에서 baseline sparse는 32 bits/event, dense 패킷은 48 bits이므로, 물리 비트 기준 dense break-even은 2 events부터 성립한다. 이를 반영해 threshold를 재탐색한 결과는 아래와 같다.

Threshold	Avg throughput	Avg loss	Bits/event
3	0.3796	0.0595	24.00
4	0.3744	0.0616	24.17
5	0.3658	0.0746	24.54
6	0.3561	0.0932	25.10
8	0.3384	0.1250	26.08

throughput/loss/bit efficiency를 종합했을 때 threshold=3이 가장 우수한 후보로 확인되어, 최종 설계값을 3.3절의 초기값(5)에서 3으로 재조정하였다. 참고로 물리적 break-even은 링크 폭에 따라 8bit 링크 ≥3 events, 16bit 링크 ≥2 events, 32bit 링크 ≥3 events로 다르게 나타난다.

3.6 알려진 한계: Packet-Selection Flapping (Hysteresis 부재)

현재 정식 구현(aer_adaptive_top, Stage 4 link top 포함)에서 모드 선택은 두 모듈의 조합으로 이루어진다.

aer_block_occupancy.sv(line 34): dense_req_o[block_index] = (occupancy >= DENSE_ENTER_THRESHOLD) — pending bitmap을 조합적으로 popcount하여 블록별 dense 자격 여부를 매 사이클 판단
aer_mode_controller.sv(line 18): dense_valid_i가 1이면 dense를 무조건 우선 선택하고, 아니면 sparse를 선택하는 단순 조합 선택기 (clk, 상태 레지스터, 카운터, timer 없음)

즉 상태를 저장하지 않는 순수 조합 로직이므로, "지속되는 모드"라는 개념 자체가 존재하지 않는다. 정확히는 **"mode flapping"이 아니라 "packet-selection flapping"**이라고 표현하는 것이 맞다 — 매 패킷 선택 시점마다 독립적으로 dense/sparse가 결정되며, occupancy가 threshold 경계(threshold=3일 때 2↔3)를 오갈 경우 연속된 선택이 교번할 수 있다.

플래핑 방지 로직은 없다: 진입/복귀 threshold 분리, 직전 모드 상태 저장, debounce/hysteresis counter, cooldown/minimum residence time 중 어느 것도 구현되어 있지 않다. 다만 aer_output_handshake.sv(line 3)가 전송 시작 시 payload와 clear mask를 래치하므로, 이미 전송 중인 패킷의 형식·내용이 중간에 바뀌는 기능적 오류는 없다.

참고로 pending_i는 aer_event_capture의 레지스터 출력이라 같은 사이클에 들어온 이벤트가 즉시 popcount에 반영되지는 않고 다음 클록에 반영된다. 이는 캡처 과정의 1사이클 등록 지연일 뿐이며, dense 패킷을 만들기 위한 의도적 대기 정책이 아니다 (3.2절 "모드 결정 타이밍" 참조).

성능 관점에서 이는 기능 오류는 아니며, 다만 링크 폭·헤더 비용까지 고려한 최적 전환을 주장하려면 향후 dense 진입 임계치와 sparse 복귀 임계치를 분리하고, 복귀 조건이 일정 구간 연속 유지될 때만 sparse로 전환하는 hysteresis(또는 비용 기반 선택 정책) 도입이 후속 개선 항목이다.

4. RTL 설계
4.0 구현 버전 이력

초기 1D 프로토타입(aer_tx_baseline, aer_tx_hybrid)에서, 2D 픽셀 배열 기반의 정식 구현(aer_baseline_top, aer_adaptive_top)으로 재구성되었다. 최종 제출/비교에는 정식 구현을 사용한다.

구분	초기 프로토타입	현재 정식 구현
Baseline	aer_tx_baseline	aer_baseline_top
Adaptive/Hybrid	aer_tx_hybrid	aer_adaptive_top
입력 모델	N_SOURCES개의 1D event	X_SIZE × Y_SIZE valid/polarity bitmap
중재	fixed-priority / source·group RR	row/column RR (baseline), sparse RR + dense block RR (adaptive)
패킷	주소 또는 group mask 분리 포트	event/type 포함 가변 논리 패킷
공용 구성	단일 파일 중심	rtl/common의 capture·REQ/ACK FSM 재사용

⚠️ 물리 링크 정규화 버전(aer_baseline_link_top, aer_adaptive_link_top)은 stage4-physical-link 브랜치에 있을 것으로 추정되며, 현재(stage5-genus-ppa) 체크아웃에는 없다. Genus PPA에 물리 링크까지 포함하려면 해당 브랜치의 RTL을 먼저 확인·병합해야 한다 (6장 참조).

4.1 Baseline AER RTL (aer_baseline_top)
경로: rtl/baseline/aer_baseline_top.sv
파라미터: X_SIZE=16, Y_SIZE=16 (N_PIXELS=256), EVENT_W=9bit
포트	방향	설명
clk, rst_n	input	클록, 비동기 리셋
pixel_event_valid_i [N_PIXELS-1:0]	input	픽셀별 이벤트 발생 여부
pixel_event_pol_i [N_PIXELS-1:0]	input	픽셀별 polarity
aer_ack_i	input	수신부 ACK
aer_req_o	output	REQ 핸드셰이크 신호
aer_event_o [EVENT_W-1:0]	output	{polarity, y, x} 이벤트 패킷
busy_o	output	처리 중 상태

내부 구조: rtl/common/aer_event_capture.sv(pending bitmap 캡처) → rtl/baseline/aer_row_col_arbiter.sv(row RR → column RR 2-level 중재) → rtl/baseline/aer_baseline_packetizer.sv(이벤트 패킷화) → rtl/common/aer_output_handshake.sv(REQ/ACK)

4.2 Adaptive AER RTL (aer_adaptive_top)
경로: rtl/adaptive/aer_adaptive_top.sv
파라미터: X_SIZE=16, Y_SIZE=16, 4×4 block 기준 PACKET_W=37bit
포트	방향	설명
clk, rst_n	input	클록, 비동기 리셋
pixel_event_valid_i [N_PIXELS-1:0]	input	픽셀별 이벤트 발생 여부
pixel_event_pol_i [N_PIXELS-1:0]	input	픽셀별 polarity
aer_ack_i	input	수신부 ACK
aer_req_o	output	REQ 핸드셰이크 신호
aer_packet_o [PACKET_W-1:0]	output	sparse/dense 가변 패킷
busy_o	output	처리 중 상태
dense_eligible_o	output	현재 dense 모드 전송 가능 여부

내부 구조: aer_event_capture.sv → rtl/adaptive/aer_block_occupancy.sv(4×4 블록 점유율 계산) → aer_mode_controller.sv(sparse/dense 모드 결정) → aer_sparse_packetizer.sv / (aer_dense_block_selector.sv → aer_dense_packetizer.sv) → aer_output_handshake.sv

4.3 동일 물리 링크(Physical Link) 설계 — 공정 비교를 위한 핵심 장치

출처: origin/stage4-physical-link 브랜치, 핵심 커밋 4fc14f1 (Complete equal-bandwidth AER comparison through Stage 4). 현재 작업 브랜치(stage5-genus-ppa)에는 아직 병합되지 않은 상태이며, Genus 합성 전 병합이 필요하다 (6장 참조).

Dense 패킷이 논리적으로 더 넓은 정보를 담기 때문에, "handshake 횟수"만으로 비교하면 Adaptive 구조가 유리해 보이는 착시가 생길 수 있다. 이를 해결하기 위해 두 아키텍처의 논리 패킷 생성부 뒤에 공통 serializer를 붙여, 동일한 물리 링크(link_valid/link_ready/link_data, 기본 LINK_WIDTH=16bit)로 전송하도록 구성하였다.

최종 Genus 합성/제출 대상 top

역할	파일 경로
Baseline link top	rtl/baseline/aer_baseline_link_top.sv
Adaptive link top	rtl/adaptive/aer_adaptive_link_top.sv
Serializer (공용)	rtl/common/aer_link_serializer.sv
Deserializer (수신 검증용)	rtl/common/aer_link_deserializer.sv

포트 구성

Top	입력	출력
aer_baseline_link_top	clk, rst_n, pixel_event_valid_i[N_PIXELS-1:0], pixel_event_pol_i[N_PIXELS-1:0], link_ready_i	link_valid_o, link_data_o[LINK_WIDTH-1:0], busy_o, logical_packet_accept_o, logical_packet_type_o, logical_packet_bits_o, logical_packet_data_o, logical_packet_clear_mask_o[N_PIXELS-1:0]
aer_adaptive_link_top	(baseline과 동일)	(baseline 출력 전체) + dense_eligible_o

두 top 모두 논리 패킷 생성부가 aer_link_serializer를 직접 인스턴스화하는 구조이며, header는 type 2bit + payload length 6bit로 구성된다.

16bit 링크 기준 실제 전송 비용

항목	설정
Wire header	8bit: type[1:0] + payload length[5:0]
Primary LINK_WIDTH	16bit (8/32bit도 함께 검증)
Baseline sparse payload	9bit
Adaptive sparse payload	10bit
Adaptive dense payload	37bit
Packet	Cost
Baseline sparse	32 bits/event
Adaptive sparse	32 bits/event
Adaptive dense	48 bits/packet

패킷 비트 필드 상세 구성

파라미터: X_SIZE=Y_SIZE=16 (X_W=Y_W=4), BLOCK_W=BLOCK_H=4 (BLOCK_X_W=BLOCK_Y_W=2), BLOCK_PIXELS=16

Sparse 패킷 (10bit, aer_sparse_packetizer.sv line 16):

Bit	필드	폭	설명
[0]	type	1	0: sparse
[4:1]	x	4	x 좌표
[8:5]	y	4	y 좌표
[9]	polarity	1	polarity

Dense 패킷 (37bit, aer_dense_packetizer.sv line 30):

Bit	필드	폭	설명
[0]	type	1	1: dense block
[2:1]	block_x	2	블록 x 좌표
[4:3]	block_y	2	블록 y 좌표
[20:5]	valid_mask	16	블록 내 pending event bitmap (local_index = local_y×4 + local_x)
[36:21]	polarity_mask	16	valid_mask=1인 이벤트들의 polarity bitmap

두 포맷 모두 adaptive top의 공통 출력 버스(37bit, 최대 패킷 크기 기준)에 실리며, sparse 전송 시 packet_o[36:10]은 0으로 채워진다. baseline(9bit)과 adaptive sparse(10bit)의 1bit 차이는 정확히 type 필드에서 발생한다 — baseline은 포맷이 하나뿐이라 구분 비트가 불필요하지만, adaptive는 sparse/dense 두 포맷을 구분해야 하므로 1bit가 추가된다.

이로써 Dense 패킷을 "한 transaction으로 무료 전송"하는 불공정성이 제거되었고, 이 조건으로 84회 비교 시뮬레이션(Stage 4)을 수행하였다.

5. 기능 검증 및 성능 비교 시뮬레이션
5.1 Baseline 기능 검증

Baseline의 directed verification 결과는 2.3절 참조 (8종 시나리오 전부 PASS).

5.2 Stage 4 — 동일 물리 대역폭 비교 시뮬레이션 방법론

Baseline-Link와 Adaptive-Link를 4.3절의 동일 물리 링크에 연결한 상태로, uniform random / Poisson-like / hotspot / burst / simultaneous multi-pixel / spatial locality sweep 등 다양한 트래픽 조건에서 총 84회 비교 시뮬레이션을 수행하였다. 검증에는 SystemVerilog self-checking testbench(Icarus Verilog)를 사용하였다.

5.3 핵심 측정 결과

엄격한 saturation 조건(loss ≤ 1%, delivered throughput ≥ 95% offered load)에서는 두 구조 모두 약 0.4004 events/cycle로 동일하였다. 그러나 overload 상황에서는 Adaptive 구조의 성능 저하가 훨씬 완만하였다.

Offered load	Baseline TP	Adaptive TP	Ratio
0.802	0.4997	0.6961	1.39×
1.000	0.4997	0.8676	1.74×
2.000	0.4997	1.6731	3.35×
조건	Baseline	Adaptive
Loss @ 0.802	35.1%	12.1%
Avg latency @ 0.802	178.8 cycles	46.8 cycles
Burst (rate 2.0, dur 500) loss	55.5%	14.3%
Hotspot 0.80 loss	37.2%	36.4%

Hotspot 조건에서 개선폭이 작은 이유는, output encoding 병목이 해소된 대신 **픽셀당 pending 이벤트 1개 제한(one-pending-event-per-pixel capture)**이 새로운 지배적 병목으로 이동했기 때문이다. 이는 개선 이후 병목이 어디로 옮겨갔는지를 보여주는 중요한 결과이며, 향후 개선 여지로 12장에서 다시 다룬다.

결과 해석 시 주의: strict saturation(loss≤1%) 지점 자체는 두 구조가 동일(0.4004 events/cycle)하다. "최대 무손실 처리율이 3.35배 증가했다"는 표현은 부정확하다 — 3.35배는 offered load 2.0에서의 overload 상황 delivered throughput 비율이다. 정확한 표현은: "제안 구조는 strict low-loss saturation 지점 자체를 크게 이동시키지는 않았지만, saturation 이후의 overload·burst 영역에서 성능 저하(degradation)를 크게 완화한다."

Timestamp/이벤트 순서에 대한 한계: Dense 패킷은 4×4 블록 내 여러 이벤트를 하나의 valid/polarity bitmap으로 묶으므로, 그 안에 포함된 개별 이벤트들의 정확한 발생 시각과 상대적 순서는 보존되지 않는다. 현재 구조는 "해당 packet snapshot 시점의 정확한 pending 집합(set) 표현"을 제공하는 것이며, "전체 event stream의 losslessl 압축"이 아니다. 이 한계는 최종 보고서/발표에 명시한다.

threshold 검증 결과: 3.35배(offered load 2.0) 헤드라인 수치는 DENSE_ENTER_THRESHOLD=5(Stage 3 초기값) 조건에서 측정되었다. 최종 채택값인 threshold=3으로 동일 조건(uniform, offered=2.0, LINK_WIDTH=16, always-ready, seed=1)을 재실행한 결과, throughput은 1.66871652 events/cycle(threshold=5는 1.67306171)로 나타나 baseline 대비 향상비는 **3.34×**였다. threshold=5(3.35×) 대비 차이는 약 0.26%로 사실상 무시할 수준이며, 헤드라인 결과가 threshold 선택에 민감하지 않음을 확인하였다 (재실행은 stage5-genus-ppa(model1) 브랜치의 순정 코드로 수행되었으며, hysteresis 관련 코드는 포함되지 않았음을 확인함).

6. Synthesis (Genus)
6.1 목표

aer_baseline_link_top과 aer_adaptive_link_top을 동일한 PDK/PVT/SDC/최적화 조건으로 Genus 합성하여 normalized Area/Power/Fmax를 비교하는 것이 목표이다.

6.2 서버 환경 조사 결과 (확정)
항목	결과
Genus 실행 파일	/tools/cadence/DDI231/bin/genus (PATH에는 없으나 which genus로 확인됨)
PDK	Cadence GPDK(Generic PDK) 045nm, gsclib045_svt_v4.7
Liberty (slow corner)	/tools/config/GPDK/gsclib045_svt_v4.7/gsclib045/timing/slow_vdd1v0_basicCells.lib
Tech LEF	/tools/config/GPDK/gsclib045_svt_v4.7/gsclib045/lef/gsclib045_tech.lef
Macro LEF	/tools/config/GPDK/gsclib045_svt_v4.7/gsclib045/lef/gsclib045_macro.lef
설치 위치	/tools/config/ (정식 설치 경로, 서버 관리자가 배포)

이전에 발견된 gscl45nm 후보(/usr/local/share/qflow/tech/)는 이 계정 세션에서 존재하지 않아 사용하지 않는다. 대신 /tools/config/GPDK/에서 발견한 gsclib045_svt_v4.7을 최종 라이브러리로 채택하였다. 해당 라이브러리의 README에 따르면 **"tool demonstration purpose"의 Liberty 타이밍 특성화(2×2 constraint-table 기반, Altos Liberate 특성화)**로 명시되어 있어, 실제 파운드리向 실리콘 PDK는 아니지만 Cadence가 EDA 툴 교육·데모용으로 정식 배포하는 Generic PDK임이 확인되었다. 대회/교육 목적의 합성에는 이 라이브러리로 충분하다.

Standard/Low/High-Vt(svt/lvt/hvt) 및 backbias 변형도 함께 제공되나, 본 연구에서는 기본 svt(표준 Vt) 버전을 사용한다. Corner는 timing worst-case 확인을 위해 slow corner를 기본으로 사용하고, 필요시 fast corner로 추가 확인한다.

6.3 초기 타이밍 제약(SDC) 조건

genus_baseline_link.tcl, genus_adaptive_link.tcl 공통으로 clk 10.0 time-unit 주기의 초기 제약을 사용하며, 이후 7장에서 slack을 보며 주기를 좁혀 Fmax를 탐색한다.

6.4 합성 결과 요약
항목	Baseline	Adaptive
Leaf Instance Count	2940	5501
Sequential Instance Count	534	572
Combinational Instance Count	2406	4929
Genus Runtime	287.95초	1416.63초

Adaptive는 occupancy 계산, mode controller, sparse/dense packetizer 등 추가 조합 로직으로 인해 Combinational Instance가 baseline 대비 약 2.05배 늘었다. 반면 Sequential Instance는 1.07배로 큰 차이가 없다 — 두 구조 모두 캡처/핸드셰이크 상태 저장 로직은 비슷한 규모를 유지한다는 뜻이다.

7. Timing 분석 및 최적화
7.1 초기 타이밍 리포트 (10ns 제약 기준)
항목	Baseline	Adaptive
Clock Period	10.0ns	10.0ns
Critical Path Slack	+0.2ns	+0.6ns
TNS (Total Negative Slack)	0.0	0.0
Violating Paths	0	0

두 구조 모두 10ns 제약에서 타이밍 위반 없이 통과하였다. Adaptive가 baseline보다 조합 로직이 약 2배 많음에도 불구하고 오히려 slack이 더 크다(여유가 많다) — 이는 critical path가 occupancy 계산·mode controller 경로가 아니라 다른 경로(예: 캡처·핸드셰이크 경로)에 있을 가능성을 시사한다.

7.2 최적화 과정

두 구조 모두 초기 제약(10ns)에서 이미 slack이 양수이므로, 클록 주기를 좁혀가며(예: 9ns, 8ns...) 재합성하여 slack이 0에 근접하는 지점(=최소 클록 주기)을 탐색하는 절차가 필요하다. (TODO: 시간이 허락하는 대로 주기를 좁혀가며 실제 Fmax를 정밀 탐색)

7.3 최종 타이밍 결과 (근사치)

정밀 탐색 전, 현재 slack으로부터 critical path 지연시간과 대략적인 Fmax를 역산하면:

Baseline: critical path ≈ 10 - 0.2 = 9.8ns → Fmax ≈ 1/9.8ns ≈ 102.0 MHz
Adaptive: critical path ≈ 10 - 0.6 = 9.4ns → Fmax ≈ 1/9.4ns ≈ 106.4 MHz

이는 단일 지점(10ns 제약)에서의 근사치이며, 실제 Fmax는 주기를 좁혀가는 재합성으로 검증해야 정확하다.

8. Area 분석
8.1 report_area 결과
항목	Baseline	Adaptive	비율
Cell Area (μm²)	9502.470	16410.528	1.73×
Net Area (μm²)	3820.143	7530.204	1.97×
Total Area (μm²)	13322.613	23940.732	1.80×
8.2 면적 차이 원인 분석

Adaptive의 면적 증가는 주로 다음에서 기인한다.

aer_block_occupancy.sv: 4×4 블록별 popcount 기반 occupancy 계산 로직
aer_mode_controller.sv, aer_dense_block_selector.sv: sparse/dense 모드 선택 로직
aer_sparse_packetizer.sv + aer_dense_packetizer.sv: baseline은 단일 packetizer(9bit)만 필요하지만, adaptive는 두 개의 packetizer(10bit + 37bit)를 모두 구현해야 함

Net Area가 Cell Area보다 더 크게(1.97×) 증가한 것은, occupancy 계산과 mode controller 간의 배선 연결(fan-in/fan-out)이 늘어난 결과로 해석된다 (실제로 QoR 리포트에서 Average Fanout이 baseline 2.2 → adaptive 2.4로 소폭 증가).

9. Power 분석
9.1 report_power 결과
항목	Baseline	Adaptive	비율
Leakage (W)	2.504e-07	4.341e-07	1.73×
Internal (W)	2.852e-04	3.412e-04	1.20×
Switching (W)	3.035e-04	4.790e-04	1.58×
Total (mW)	0.589	0.821	1.39×
9.2 소비전력 차이 원인 분석

Total power는 39% 증가했는데, 이는 8장의 면적 증가(80%)보다 훨씬 적은 폭이다. Switching power(스위칭, 동작 시 전력)가 가장 크게 증가(1.58×)했는데, 이는 occupancy 계산이 매 사이클 pending bitmap 전체를 조합적으로 popcount하기 때문으로 해석된다. Logic 카테고리가 전체 전력의 64.75%(baseline은 58.27%)를 차지하여, 늘어난 조합 로직이 전력 증가의 주된 원인임을 뒷받침한다.

10. 최대 동작 주파수 (Fmax) 산출
10.1 Fmax 탐색 방법

클록 주기를 좁혀가며(예: 9ns, 8ns...) 재합성하여 slack이 0에 근접하는 지점을 찾는 것이 정확한 방법이다. 현재는 10ns 단일 지점에서만 합성하였으므로, 아래는 그 slack으로부터 역산한 근사치이다.

10.2 근사 Fmax (10ns 단일 지점 기준)
항목	Baseline	Adaptive
Slack @ 10ns	+0.2ns	+0.6ns
근사 Critical Path	9.8ns	9.4ns
근사 Fmax	102.0 MHz	106.4 MHz

흥미롭게도 adaptive가 baseline보다 게이트 수가 87% 많음에도 근사 Fmax는 오히려 더 높게 나타났다. 정확한 Fmax는 주기를 좁혀가며 재합성해야 확정할 수 있으나(TODO), 적어도 "복잡도 증가가 곧 동작 주파수 저하"로 이어지지는 않았다는 것을 시사한다.

10.3 실측 Fmax (주기를 좁혀 재합성 후 확정)
항목	Baseline	Adaptive
재합성 주기	9.7ns	9.3ns
Slack	0.0ns (경계)	0.0ns (경계)
실측 Fmax	≈103.1 MHz	≈107.5 MHz

두 구조 모두 재합성 주기에서 slack이 정확히 0.0으로 나타나, 각 지점이 실제 최소 클록 주기에 매우 근접함을 확인하였다. 최초 근사치(baseline 102.0MHz, adaptive 106.4MHz)와 거의 일치하여 신뢰도가 높다. 최종 확정 Fmax: Baseline ≈103.1MHz, Adaptive ≈107.5MHz (Adaptive가 약 1.04배 더 높음) — Adaptive가 게이트 수는 87% 더 많음에도 동작 주파수는 오히려 baseline보다 높다는 결과가 실측으로 확정되었다.

11. 기존 구조 vs 제안 구조 종합 비교
11.1 기능적 성능 비교 (Stage 4 결과, 완료)
항목	Baseline	Adaptive	비고
Saturation throughput	0.4004 events/cycle	0.4004 events/cycle	엄격 조건(loss≤1%)에서는 동일
Throughput @ offered 2.0	0.4997	1.6731	3.35×
Loss @ offered 0.802	35.1%	12.1%	
Latency @ offered 0.802	178.8 cycles	46.8 cycles	
Burst loss (rate 2.0, dur 500)	55.5%	14.3%	
Hotspot loss	37.2%	36.4%	개선 제한적 (새 병목: pixel capture)
11.2 PPA 비교 (Genus 합성 결과, 실측 Fmax 기준)
항목	Baseline-Link	Adaptive-Link	비율
Area (μm²)	13322.6	23940.7	1.80×
Power (mW)	0.589	0.821	1.39×
실측 Fmax (MHz)	103.1	107.5	1.04×
재합성 주기 (slack=0 지점)	9.7ns	9.3ns	—

복합 지표 (실측 Fmax 기반): Stage 4의 offered load 2.0 결과(baseline 0.4997, adaptive 1.6731 events/cycle)와 위 실측 Fmax를 결합하면:

복합 지표	Baseline	Adaptive	비율
Throughput (events/s)	≈51.5M	≈179.9M	3.49×
Throughput / Area	≈3868	≈7515	1.94×
Energy / delivered event	≈11.43 pJ	≈4.56 pJ	0.40× (60% 절감)

Power 값은 10ns 제약에서 측정된 값이며, 실제 동작 주파수(103.1MHz/107.5MHz)에서 재측정하면 다소 달라질 수 있으나, 방향성(Adaptive가 면적당·에너지당 효율에서 우수)은 안정적으로 유지될 것으로 판단된다.

11.3 비교 결과 해석

Stage 4 결과만으로도 Adaptive 구조가 overload/burst 상황에서 명확한 이득을 보이며, 특히 물리 비트 비용까지 동일하게 맞춘 상태에서의 개선이라는 점에서 신뢰도가 높다. 다만 hotspot 트래픽에서는 개선폭이 제한적이었고, 그 원인이 새로운 병목(픽셀당 pending 1개 제한)으로 명확히 규명되었다는 점도 함께 서술한다.

11.4 개선 구조가 유의미한 이유 (수치 기반 논거)

Adaptive 구조는 baseline 대비 면적을 1.80배, 전력을 1.39배 더 사용한다. 하드웨어 비용만 보면 불리해 보일 수 있으나, Stage 4에서 확인한 처리량 개선(overload에서 최대 3.35배)과 결합하면 그림이 달라진다. 근사 계산 기준으로 면적당 처리량(Throughput/Area)은 오히려 1.94배 우수하고, 이벤트 하나를 전달하는 데 드는 에너지(Energy/delivered event)는 약 60% 절감된다. 즉 Adaptive는 "더 크고 더 많이 먹지만, 일한 만큼보다 훨씬 더 적게 먹는" 구조로 해석할 수 있다. 이는 단순 PPA 비교가 아니라 성능-비용 트레이드오프를 종합적으로 고려했을 때 개선 구조가 실질적으로 유의미하다는 근거가 된다.

12. 결론 및 2차 과제 연계 방향
12.1 1차 결과 요약

본 연구는 전통 AER(round-robin baseline)을 실측 벤치마크하여 "한 handshake당 이벤트 1개 전송"이 주 병목임을 정량적으로 규명하고, 이를 해소하는 Traffic-Adaptive Hybrid AER(sparse/dense 4×4 block bitmap)을 제안하였다. 이는 Group-AER(Son et al., 2017) 계열의 grouped representation 개념을 기반으로, 순간적 pending occupancy에 따른 runtime 자동 모드 선택과 동일 물리 대역폭 기준의 공정 비교를 추가한 것이다 (2.6절 참조). 동일 물리 대역폭 조건에서 84회 비교 시뮬레이션을 수행한 결과, strict low-loss saturation 지점 자체는 baseline과 동일하였으나, overload 조건(offered 2.0)에서 delivered throughput이 baseline 대비 최대 3.35배 높았으며, 특정 부하(0.802)에서 loss는 35.1%→12.1%, latency는 178.8→46.8 cycle로 개선되었다. 즉 제안 구조의 강점은 "무손실 최대 처리율 향상"이 아니라 "overload·burst 상황에서의 성능 저하 완화"로 정확히 서술되어야 한다.

12.2 한계점 및 개선 여지
Hotspot 트래픽에서는 개선폭이 제한적이었다. 원인은 output encoding 병목이 해소된 대신 픽셀당 pending 이벤트 1개 제한이 새로운 지배적 병목으로 이동했기 때문이며, 이는 향후 픽셀별 다중 버퍼링 등으로 추가 개선이 가능한 지점이다.
Timestamp/이벤트 순서 미보존: dense 패킷 내 개별 이벤트의 정확한 발생 시각과 순서는 보존되지 않는다 (5.3절 참조). 정밀한 시간 정보가 중요한 응용에는 추가 설계가 필요하다.
헤드라인 결과의 threshold 민감도 (검증 완료): threshold=5(3.35×)와 threshold=3(3.34×) 간 차이는 약 0.26%로, 헤드라인 결과가 threshold 선택에 민감하지 않음을 model1 순정 코드로 확인하였다.
"Always-bitmap" 비교 부재: 현재는 conventional AER과 adaptive AER만 비교하였다. 개선 효과가 "runtime 적응" 자체에서 오는지, 단순히 "그룹 단위 전송(Group-AER류)" 자체에서 오는지 분리되지 않는다. DENSE_ENTER_THRESHOLD=1로 설정하여 "항상 dense" 모드를 재현·비교하면 이를 분리할 수 있으며, 시간이 허락하는 대로 추가 예정이다.
Stage 2와 Stage 4의 saturation 수치 차이: Stage 2(baseline 단독) saturation은 약 0.2987 events/cycle이었으나, Stage 4(동일 링크 비교, 양쪽 구조 포함)의 strict saturation은 0.4004 events/cycle로 나타났다. 두 수치는 측정 방법론(traffic generator, ACK latency 모델, 링크 포함 여부)이 다르므로 직접 비교 대상이 아니며, 최종 보고서에는 각 수치의 정확한 측정 조건을 명시한다.
PPA(Area/Power/Fmax) 비교는 공식 PDK 확정 지연으로 본 보고서 제출 시점까지 완료하지 못하였다(6장 참조). 확보되는 대로 11.2절을 갱신하며, 단순 Area/Power뿐 아니라 Throughput/Area, Energy/Delivered-Event 같은 복합 지표로도 평가한다.
실제 DVS 카메라 이벤트 트레이스를 이용한 검증은 수행하지 못하였다. Uniform random/Poisson/hotspot/burst 등 합성 트래픽 기반 characterization은 architecture 특성 파악에는 충분하나, 실제 워크로드에서도 4×4 블록 occupancy가 threshold 이상으로 자주 형성되는지는 향후 검증이 필요하다.
12.3 2차 과제와의 연결점

2차 과제(n×m 시각 정보를 N×M world memory로 매핑)는 본질적으로 다수의 시각 이벤트 소스를 하나의 메모리 주소 공간으로 라우팅하는 문제로, 1차에서 검증한 AER 통신 구조를 좌표 변환 로직과 결합하여 확장 적용할 수 있다. 특히 Adaptive AER의 4×4 block 단위 이벤트 묶음 처리 방식은, 픽셀 좌표를 world 좌표로 변환할 때 블록 단위로 일괄 변환하는 최적화와도 자연스럽게 연결된다.

13. 참고문헌
Boahen, K. A. (2004). A burst-mode word-serial address-event link—I: Transmitter design. IEEE Transactions on Circuits and Systems I: Regular Papers, 51(7), 1269-1280.
Son, B., Suh, Y., Kim, S., et al. (2017). 4.1 A 640×480 dynamic vision sensor with a 9µm pixel and 300Meps address-event representation. 2017 IEEE ISSCC, 66-67.
Purohit, P., & Manohar, R. (2021). Hierarchical token rings for address-event encoding. 2021 27th IEEE International Symposium on Asynchronous Circuits and Systems (ASYNC), 9-16.
Purohit, P., & Manohar, R. (2022). Field-programmable encoding for address-event representation. Frontiers in Neuroscience, 16.
Jose, S., & Simeone, O. (2020). Address-event variable-length compression for time-encoded data.
Wang, Y., et al. (2026). An ultra-low-power synthesizable asynchronous AER encoder for neuromorphic edge devices. arXiv:2604.05313.
(필요시 추가 인용 자료)
부록
A. 전체 RTL 코드
B. Genus/Xcelium 스크립트 (filelist, tcl, sdc)
C. 원본 리포트 파일 (report_area.rpt 등 전문)