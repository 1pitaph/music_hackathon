import { Pressable, StyleSheet, View } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import Animated, { useAnimatedStyle, useSharedValue, withSequence, withSpring } from 'react-native-reanimated';

import { IconSymbol } from '@/components/ui/icon-symbol';
import { ThemedText } from '@/components/themed-text';
import { AppleColors, AppleRadius, AppleType, Spacing } from '@/constants/theme';

const AP = Animated.createAnimatedComponent(Pressable);

interface Props {
  title: string; host: string; color: string;
  /** 当前歌曲名，显示在播放器主体区域 */
  songTitle?: string;
  isPlaying: boolean; onPlayToggle: () => void;
  onPrev: () => void; onNext: () => void;
  onExpandPlayer?: () => void;
}

/** 悬浮播放器 — 暂停/播放只切图标，不隐藏。非按钮区域预留展开详情页。 */
export function FloatingPlayer({ title, host, color, isPlaying, onPlayToggle, onPrev, onNext, onExpandPlayer }: Props) {
  const sc = useSharedValue(1);
  const aS = useAnimatedStyle(() => ({ transform: [{ scale: sc.value }] }));

  const handlePlayPause = () => {
    sc.value = withSequence(
      withSpring(0.94, { damping: 14, stiffness: 400 }),
      withSpring(1.03, { damping: 10, stiffness: 300 }),
      withSpring(1, { damping: 10, stiffness: 300 }),
    );
    onPlayToggle();
  };

  return (
    <View style={styles.anc} pointerEvents="box-none">
      {/* 非按钮区域 — 点击预留展开全屏播放器 */}
      <Pressable onPress={onExpandPlayer} style={styles.cap}>
        {/* 小封面 */}
        <LinearGradient colors={[color, color + 'CC']} start={{ x: 0, y: 0 }} end={{ x: 1, y: 1 }} style={styles.cv} />

        {/* 信息 */}
        <View style={styles.inf}>
          <ThemedText style={styles.tt} numberOfLines={1} lightColor={AppleColors.label} darkColor={AppleColors.label}>{title}</ThemedText>
          <ThemedText style={styles.sh} numberOfLines={1} lightColor={AppleColors.secondaryLabel} darkColor={AppleColors.secondaryLabel}>{host}</ThemedText>
        </View>

        {/* 控件 — 每个独立按钮，不冒泡到父容器 */}
        <View style={styles.ct} pointerEvents="auto">
          <Pressable onPress={onPrev} hitSlop={8} style={({ pressed }) => [pressed && { opacity: 0.5 }]}>
            <IconSymbol size={20} name="backward.fill" color={AppleColors.secondaryLabel} />
          </Pressable>

          <AP onPress={handlePlayPause} style={[styles.pb, aS]}>
            <IconSymbol size={22} name={isPlaying ? 'pause.fill' : 'play.fill'} color="#FFFFFF" />
          </AP>

          <Pressable onPress={onNext} hitSlop={8} style={({ pressed }) => [pressed && { opacity: 0.5 }]}>
            <IconSymbol size={20} name="forward.fill" color={AppleColors.secondaryLabel} />
          </Pressable>
        </View>
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  anc: { position: 'absolute', bottom: 0, left: 0, right: 0, alignItems: 'center', paddingBottom: 14 },
  cap: {
    flexDirection: 'row', alignItems: 'center',
    width: '88%', height: 60,
    backgroundColor: 'rgba(38,34,30,0.72)',
    borderRadius: AppleRadius.player,
    borderWidth: 0.5, borderColor: 'rgba(255,255,255,0.08)',
    paddingHorizontal: Spacing.lg, gap: Spacing.md,
    shadowColor: '#000', shadowOffset: { width: 0, height: 14 }, shadowOpacity: 0.35, shadowRadius: 40, elevation: 20,
  },
  cv: { width: 42, height: 42, borderRadius: AppleRadius.thumb },
  inf: { flex: 1, gap: 1 },
  tt: { ...AppleType.footnote, fontWeight: '600' },
  sh: { ...AppleType.caption2 },
  ct: { flexDirection: 'row', alignItems: 'center', gap: Spacing.lg },
  pb: {
    width: 40, height: 40, borderRadius: 20,
    backgroundColor: AppleColors.accent,
    alignItems: 'center', justifyContent: 'center',
    shadowColor: AppleColors.accent, shadowOffset: { width: 0, height: 4 }, shadowOpacity: 0.3, shadowRadius: 8,
  },
});
