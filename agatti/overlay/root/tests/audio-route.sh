#!/bin/sh
# Route the UNO Q sound card for headphone playback (MultiMedia1 ->
# RX_CODEC_DMA_RX_0 -> RX macro RX0/RX1 -> INT0/INT1 -> PM4125 HPHL/HPHR)
# and, with "capture", for recording from AMIC2 into MultiMedia1.
#   ./audio-route.sh [playback|capture|off]
C=$(aplay -l 2>/dev/null | grep '^card' | grep -v Loopback | head -1 | sed 's/^card \([0-9]*\).*/\1/')
[ -n "$C" ] || { echo "no UNO Q sound card"; exit 1; }
set_() { amixer -q -c "$C" cset name="$1" "$2" || echo "  could not set '$1' = $2"; }
case ${1:-playback} in
playback)
	set_ 'RX_CODEC_DMA_RX_0 Audio Mixer MultiMedia1' 1
	set_ 'RX_MACRO RX0 MUX' AIF1_PB
	set_ 'RX_MACRO RX1 MUX' AIF1_PB
	set_ 'RX INT0_1 MIX1 INP0' RX0
	set_ 'RX INT1_1 MIX1 INP0' RX1
	set_ 'RX INT0 DEM MUX' CLSH_DSM_OUT
	set_ 'RX INT1 DEM MUX' CLSH_DSM_OUT
	set_ 'RX_RX0 Digital Volume' 80
	set_ 'RX_RX1 Digital Volume' 80
	set_ 'HPHL_RDAC Switch' 1
	set_ 'HPHR_RDAC Switch' 1
	set_ 'HPHL Switch' 1
	set_ 'HPHR Switch' 1
	set_ 'HPHL Volume' 20
	set_ 'HPHR Volume' 20
	echo "card $C routed for headphone playback on MultiMedia1 (hw:$C,0)"
	;;
capture)
	set_ 'MultiMedia1 Mixer TX_CODEC_DMA_TX_3' 1
	set_ 'TX DEC0 MUX' SWR_MIC
	set_ 'ADC2 MUX' INP2
	set_ 'ADC2_MIXER Switch' 1
	set_ 'ADC2 Switch' 1
	set_ 'ADC2 Volume' 8
	echo "card $C routed for AMIC2 capture on MultiMedia1 (hw:$C,0)"
	;;
off)
	set_ 'RX_CODEC_DMA_RX_0 Audio Mixer MultiMedia1' 0
	set_ 'HPHL Switch' 0
	set_ 'HPHR Switch' 0
	set_ 'MultiMedia1 Mixer TX_CODEC_DMA_TX_3' 0
	;;
esac
