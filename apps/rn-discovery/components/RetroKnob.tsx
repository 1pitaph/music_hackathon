import { Pressable, StyleSheet, View } from 'react-native';
import Animated, {
  Easing,
  runOnJS,
  useAnimatedStyle,
  useSharedValue,
  withSequence,
  withSpring,
  withTiming,
} from 'react-native-reanimated';

import { AppleColors } from '@/constants/theme';

const AnimatedPressable = Animated.createAnimatedComponent(Pressable);

const KNOB_SIZE = 72;
const ROTATION_DEGREES = 20;

interface RetroKnobProps {
  onTurn: () => void;
}

/**
 * 调频控件 — Apple Watch Digital Crown 美学。
 *
 * 极简圆形：细环边框 + 浅灰填充 + 红色指示点。
 * 无滚花纹理、无铆钉、无装饰——精确、克制。
 * 点击：20° 旋转 → onTurn → 弹簧回弹。
 */
export function RetroKnob({ onTurn }: RetroKnobProps) {
  const rotation = useSharedValue(0);

  const animatedStyle = useAnimatedStyle(() => ({
    transform: [{ rotate: `${rotation.value}deg` }],
  }));

  const handlePress = () => {
    rotation.value = withSequence(
      withTiming(ROTATION_DEGREES, {
        duration: 180,
        easing: Easing.out(Easing.cubic),
      }),
      withTiming(ROTATION_DEGREES, { duration: 40 }, () => {
        runOnJS(onTurn)();
      }),
      withSpring(0, { damping: 14, stiffness: 160 }),
    );
  };

  return (
    <AnimatedPressable onPress={handlePress}>
      <Animated.View style={[styles.knob, animatedStyle]}>
        {/* 指示点 — 红色，12点钟方向 */}
        <View style={styles.indicatorDot} />
        {/* 中心固定点 */}
        <View style={styles.centerDot} />
      </Animated.View>
    </AnimatedPressable>
  );
}

const styles = StyleSheet.create({
  knob: {
    width: KNOB_SIZE,
    height: KNOB_SIZE,
    borderRadius: KNOB_SIZE / 2,
    // 浅灰填充 + 细环边框
    backgroundColor: 'rgba(120,120,128,0.08)',
    borderWidth: 2,
    borderColor: 'rgba(60,60,67,0.18)',
    alignItems: 'center',
    justifyContent: 'center',
  },

  indicatorDot: {
    position: 'absolute',
    top: 8,
    width: 4,
    height: 4,
    borderRadius: 2,
    backgroundColor: AppleColors.accent,
  },

  centerDot: {
    width: 6,
    height: 6,
    borderRadius: 3,
    backgroundColor: 'rgba(60,60,67,0.12)',
  },
});
