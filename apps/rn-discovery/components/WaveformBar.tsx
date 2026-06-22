import { useCallback, useMemo, useState } from 'react';
import { LayoutChangeEvent, StyleSheet, View } from 'react-native';
import { Gesture, GestureDetector } from 'react-native-gesture-handler';
import { runOnJS, useSharedValue } from 'react-native-reanimated';

import { ThemedText } from '@/components/themed-text';
import { AppleColors, AppleType } from '@/constants/theme';

const BAR_COUNT = 44;
const BAR_WIDTH = 3.5;
const BAR_GAP = 1.5;
const BAR_MAX_H = 60;
const TOTAL_BAR_W = BAR_COUNT * (BAR_WIDTH + BAR_GAP) - BAR_GAP;

function generateWaveform(seed: number): number[] {
  const h: number[] = [];
  let s = seed;
  for (let i = 0; i < BAR_COUNT; i++) {
    s = (s * 16807 + 0) % 2147483647;
    h.push(0.18 + ((s % 100) / 100) * 0.82);
  }
  return h;
}

function fmtTime(sec: number): string {
  const m = Math.floor(sec / 60);
  const s = Math.floor(sec % 60);
  return `${m}:${s.toString().padStart(2, '0')}`;
}

interface Props {
  seed: number;
  progress: number;
  duration: number;
  onSeek: (p: number) => void;
  marginH: number;
}

/** 声波进度条 — 贯穿屏幕宽，时间对齐 bar 两端下方 */
export function WaveformBar({ seed, progress, duration, onSeek, marginH }: Props) {
  const waveform = useMemo(() => generateWaveform(seed), [seed]);
  const [layoutW, setLayoutW] = useState(0);
  const padXSV = useSharedValue(0);
  const padX = layoutW > 0 ? (layoutW - TOTAL_BAR_W) / 2 : 0;

  const onLayout = useCallback((e: LayoutChangeEvent) => {
    const w = e.nativeEvent.layout.width;
    setLayoutW(w);
    padXSV.value = (w - TOTAL_BAR_W) / 2;
  }, []);

  const pan = Gesture.Pan()
    .onUpdate((e) => {
      'worklet';
      const px = padXSV.value;
      const frac = Math.max(0, Math.min(1, (e.x - px) / TOTAL_BAR_W));
      runOnJS(onSeek)(frac);
    });

  const tap = Gesture.Tap()
    .onEnd((e) => {
      const frac = Math.max(0, Math.min(1, (e.x - padX) / TOTAL_BAR_W));
      onSeek(frac);
    });

  const composed = Gesture.Simultaneous(pan, tap);
  const currentTime = duration * progress;

  return (
    <View style={[styles.root, { paddingHorizontal: marginH }]}>
      <GestureDetector gesture={composed}>
        <View style={styles.barArea} onLayout={onLayout}>
          {waveform.map((h, i) => {
            const played = i / BAR_COUNT <= progress;
            return (
              <View
                key={i}
                style={[
                  styles.bar,
                  {
                    left: padX + i * (BAR_WIDTH + BAR_GAP),
                    height: BAR_MAX_H * h,
                    backgroundColor: played ? AppleColors.accent : 'rgba(245,240,232,0.14)',
                  },
                ]}
              />
            );
          })}
        </View>
      </GestureDetector>

      {/* 时间 — 紧贴 bar 起止点下方 */}
      <View style={styles.timeRow}>
        <View style={{ position: 'absolute', left: padX }}>
          <ThemedText style={styles.time} lightColor="rgba(245,240,232,0.4)" darkColor="rgba(245,240,232,0.4)">
            {fmtTime(currentTime)}
          </ThemedText>
        </View>
        <View style={{ position: 'absolute', right: padX }}>
          <ThemedText style={styles.time} lightColor="rgba(245,240,232,0.4)" darkColor="rgba(245,240,232,0.4)">
            {fmtTime(duration)}
          </ThemedText>
        </View>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  root: {},
  barArea: { position: 'relative', height: BAR_MAX_H + 6 },
  bar: { position: 'absolute', bottom: 3, width: BAR_WIDTH, borderRadius: BAR_WIDTH / 2 },
  timeRow: { position: 'relative', height: 16, marginTop: 2 },
  time: { ...AppleType.caption2 },
});
