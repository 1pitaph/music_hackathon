import { useEffect } from 'react';
import { Image } from 'expo-image';
import { Pressable, StyleSheet, View, useWindowDimensions } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import Animated, {
  Easing,
  useAnimatedStyle,
  useSharedValue,
  withSpring,
  withTiming,
} from 'react-native-reanimated';

import { IconSymbol } from '@/components/ui/icon-symbol';
import { WaveformBar } from '@/components/WaveformBar';
import { ThemedText } from '@/components/themed-text';
import { AppleColors, AppleType } from '@/constants/theme';
import { COVER_IMAGES, STATION_COLORS } from '@/data/stations';
import { Station } from '@/types/station';

const MOCK_STATION_DURATION = 25 * 60; // 25分钟模拟电台时长

interface Props {
  visible: boolean;
  station: Station;
  isPlaying: boolean;
  onClose: () => void;
  onTogglePlay: () => void;
  /** 切到上一个电台 */
  onPrevStation: () => void;
  /** 切到下一个电台 */
  onNextStation: () => void;
  onSeek: (progress: number) => void;
  progress: number;
  isFavorited: boolean;
  onToggleFavorite: () => void;
}

/** 全屏播放器 — 电台为主体，上一首/下一首切换电台 */
export function NowPlaying({
  visible, station, isPlaying,
  onClose, onTogglePlay, onPrevStation, onNextStation, onSeek,
  progress, isFavorited, onToggleFavorite,
}: Props) {
  const { width: sw, height: sh } = useWindowDimensions();
  const translateY = useSharedValue(sh);

  const color = STATION_COLORS[station.id] ?? '#8C7355';
  const COVER_MARGIN = 26;
  const coverW = sw - COVER_MARGIN * 2;
  const coverH = coverW * 0.92;

  useEffect(() => {
    if (visible) {
      translateY.value = withSpring(0, { damping: 28, stiffness: 200, mass: 0.9 });
    } else {
      translateY.value = withTiming(sh, { duration: 300, easing: Easing.inOut(Easing.cubic) });
    }
  }, [visible]);

  const overlayAS = useAnimatedStyle(() => ({
    transform: [{ translateY: translateY.value }],
  }));

  if (!visible && translateY.value === sh) return null;

  return (
    <Animated.View style={[styles.root, overlayAS]}>
      <LinearGradient
        colors={[color + '1E', color + '08', AppleColors.background]}
        locations={[0, 0.4, 1]}
        style={StyleSheet.absoluteFill}
      />

      <View style={styles.topBar}>
        <Pressable onPress={onClose} style={styles.roundBtn} hitSlop={8}>
          <IconSymbol size={20} name="chevron.down" color={AppleColors.label} />
        </Pressable>
        <View style={{ flex: 1 }} />
        <Pressable style={styles.roundBtn} hitSlop={8}>
          <IconSymbol size={18} name="ellipsis" color={AppleColors.secondaryLabel} />
        </Pressable>
      </View>

      <View style={[styles.coverWrap, { marginTop: 18, marginBottom: 16 }]}>
        <View style={[styles.coverShadow, { width: coverW, height: coverH, borderRadius: 14, backgroundColor: color + '1A' }]} />
        <View style={[styles.cover, { width: coverW, height: coverH, borderRadius: 14 }]}>
          <Image
            source={COVER_IMAGES[station.id]}
            style={StyleSheet.absoluteFill}
            contentFit="cover"
            transition={300}
          />
        </View>
      </View>

      <View style={styles.lower}>
        {/* 电台信息 — 两行：电台名 + host */}
        <View style={styles.info}>
          <ThemedText style={styles.stationName} numberOfLines={1} lightColor={AppleColors.label} darkColor={AppleColors.label}>
            {station.title}
          </ThemedText>
          <View style={styles.byRow}>
            <ThemedText style={styles.by} lightColor={AppleColors.secondaryLabel} darkColor={AppleColors.secondaryLabel}>
              by {station.hostName}
            </ThemedText>
            <Pressable onPress={onToggleFavorite} hitSlop={8} style={({ pressed }) => [pressed && { opacity: 0.5 }]}>
              <IconSymbol size={16} name={isFavorited ? 'heart.fill' : 'heart'} color={isFavorited ? AppleColors.accent : AppleColors.tertiaryLabel} />
            </Pressable>
          </View>
        </View>

        {/* 进度条 — 电台级时长 */}
        <WaveformBar
          seed={parseInt(station.id, 10) || 1}
          progress={progress}
          duration={MOCK_STATION_DURATION}
          onSeek={onSeek}
          marginH={COVER_MARGIN}
        />

        {/* 控件 — 切换电台 */}
        <View style={styles.controls}>
          <Pressable onPress={onPrevStation} hitSlop={14} style={({ pressed }) => [pressed && { opacity: 0.4 }]}>
            <IconSymbol size={36} name="backward.fill" color={AppleColors.label} />
          </Pressable>

          <Pressable onPress={onTogglePlay} hitSlop={16}>
            <IconSymbol
              size={52}
              name={isPlaying ? 'pause.fill' : 'play.fill'}
              color={AppleColors.label}
            />
          </Pressable>

          <Pressable onPress={onNextStation} hitSlop={14} style={({ pressed }) => [pressed && { opacity: 0.4 }]}>
            <IconSymbol size={36} name="forward.fill" color={AppleColors.label} />
          </Pressable>
        </View>
      </View>
    </Animated.View>
  );
}

const styles = StyleSheet.create({
  root: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: AppleColors.background,
    zIndex: 100,
    paddingTop: 60,
    paddingBottom: 20,
    flex: 1,
  },
  topBar: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 18 },
  roundBtn: {
    width: 36, height: 36, borderRadius: 18,
    backgroundColor: 'rgba(255,255,255,0.06)',
    alignItems: 'center', justifyContent: 'center',
  },
  coverWrap: { alignItems: 'center' },
  coverShadow: { position: 'absolute', top: 4, opacity: 0.25 },
  cover: { overflow: 'hidden' },
  lower: { flex: 1, justifyContent: 'space-evenly' },
  info: { alignItems: 'center', paddingHorizontal: 24 },
  stationName: { ...AppleType.title1, fontWeight: '500' as const, textAlign: 'center', letterSpacing: -0.01, marginBottom: 4 },
  byRow: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  by: { ...AppleType.subhead },
  controls: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-evenly', paddingHorizontal: 48 },
});
