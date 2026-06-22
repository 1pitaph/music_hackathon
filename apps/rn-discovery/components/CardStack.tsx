import { Gesture, GestureDetector } from 'react-native-gesture-handler';
import Animated, { Easing, cancelAnimation, runOnJS, useAnimatedStyle, useSharedValue, withSpring, withTiming } from 'react-native-reanimated';
import { StyleSheet, View, useWindowDimensions } from 'react-native';

import { StationCard } from '@/components/StationCard';
import { Station } from '@/types/station';

interface Props { stations: Station[]; currentIndex: number; isPlaying: boolean; onPlayToggle: () => void; onPrev: () => void; onNext: () => void; }

const SWIPE_RATIO = 0.25;
const SPRING = { damping: 16, stiffness: 160 };
const EASE_OUT = Easing.out(Easing.cubic);

/** 叠卡 carousel — 主卡在流内自然撑高, peek 卡片绝对定位露出侧面 */
export function CardStack({ stations, currentIndex, isPlaying, onPlayToggle, onPrev, onNext }: Props) {
  const { width: sw } = useWindowDimensions();
  const cardW = sw - 32;
  const tx = useSharedValue(0);
  const dragging = useSharedValue(false);
  const thresh = sw * SWIPE_RATIO;

  if (stations.length === 0) return null;
  const pi = (currentIndex - 1 + stations.length) % stations.length;
  const ni = (currentIndex + 1) % stations.length;

  const pan = Gesture.Pan()
    .activeOffsetX([-10, 10]).failOffsetY([-10, 10])
    .onStart(() => { cancelAnimation(tx); dragging.value = true; })
    .onUpdate(e => { tx.value = e.translationX; })
    .onEnd(e => {
      dragging.value = false;
      if (e.translationX > thresh) {
        tx.value = withTiming(sw, { duration: 300, easing: EASE_OUT }, () => { tx.value = 0; runOnJS(onPrev)(); });
      } else if (e.translationX < -thresh) {
        tx.value = withTiming(-sw, { duration: 300, easing: EASE_OUT }, () => { tx.value = 0; runOnJS(onNext)(); });
      } else {
        tx.value = withSpring(0, SPRING);
      }
    });

  const activeAS = useAnimatedStyle(() => ({
    transform: [{ translateX: tx.value }, { rotate: `${(tx.value / sw) * 2.5}deg` }],
    opacity: dragging.value ? 0.8 + 0.2 * (1 - Math.min(Math.abs(tx.value) / sw, 1)) : 1,
  }));

  return (
    <View style={styles.con}>
      {/* 左 peek — 略往下偏移，适应更高的 header */}
      <View style={[styles.peek, styles.peekL, { width: cardW }]}>
        <StationCard station={stations[pi]} isActive={false} isPlaying={false} onPlayToggle={() => {}} />
      </View>

      {/* 右 peek */}
      <View style={[styles.peek, styles.peekR, { width: cardW }]}>
        <StationCard station={stations[ni]} isActive={false} isPlaying={false} onPlayToggle={() => {}} />
      </View>

      {/* 主卡 */}
      <GestureDetector gesture={pan}>
        <Animated.View style={[styles.main, { width: cardW }, activeAS]}>
          <StationCard station={stations[currentIndex]} isActive={true} isPlaying={isPlaying} onPlayToggle={onPlayToggle} />
        </Animated.View>
      </GestureDetector>
    </View>
  );
}

const styles = StyleSheet.create({
  con: { alignItems: 'center', justifyContent: 'center' },
  main: { zIndex: 3 },
  peek: { position: 'absolute', zIndex: 1, opacity: 0.45, top: 12 },
  peekL: { left: -(8), transform: [{ translateX: -(24) }, { scale: 0.9 }, { rotate: '-3deg' }] },
  peekR: { right: -(8), transform: [{ translateX: 24 },  { scale: 0.9 }, { rotate: '3deg' }] },
});
