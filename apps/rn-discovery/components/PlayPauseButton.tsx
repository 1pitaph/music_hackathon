import { Pressable, StyleSheet, View } from 'react-native';
import Animated, {
  runOnJS,
  useAnimatedStyle,
  useSharedValue,
  withSequence,
  withSpring,
} from 'react-native-reanimated';

import { IconSymbol } from '@/components/ui/icon-symbol';
import { AppleColors } from '@/constants/theme';

const AnimatedPressable = Animated.createAnimatedComponent(Pressable);

interface PlayPauseButtonProps {
  isPlaying: boolean;
  onToggle: () => void;
  size?: number;
}

/**
 * 播放/暂停按钮 — Apple 原生风格。
 *
 * systemRed 圆形背景 + SF Symbol 白色图标。
 * 按压: Spring 0.92 → 1.05 → 1.0 弹性序列。
 * 最小触控目标 44pt (iOS HIG)。
 */
export function PlayPauseButton({
  isPlaying,
  onToggle,
  size = 44,
}: PlayPauseButtonProps) {
  const scale = useSharedValue(1);

  const pressAnimation = useAnimatedStyle(() => ({
    transform: [{ scale: scale.value }],
  }));

  const handlePress = () => {
    scale.value = withSequence(
      withSpring(0.92, { damping: 12, stiffness: 400 }),
      withSpring(1.05, { damping: 10, stiffness: 300 }),
      withSpring(1, { damping: 10, stiffness: 300 }),
    );
    runOnJS(onToggle)();
  };

  const iconSize = size * 0.45;

  return (
    <AnimatedPressable onPress={handlePress} style={pressAnimation}>
      <View
        style={[
          styles.button,
          { width: size, height: size, borderRadius: size / 2 },
        ]}
      >
        <IconSymbol
          size={iconSize}
          name={isPlaying ? 'pause.fill' : 'play.fill'}
          color="#FFFFFF"
        />
      </View>
    </AnimatedPressable>
  );
}

const styles = StyleSheet.create({
  button: {
    backgroundColor: AppleColors.accent,
    alignItems: 'center',
    justifyContent: 'center',
    // iOS 标准轻阴影
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.08,
    shadowRadius: 4,
  },
});
