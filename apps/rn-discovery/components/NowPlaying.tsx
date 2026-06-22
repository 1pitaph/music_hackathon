import { useEffect } from 'react';
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
import { STATION_COLORS } from '@/data/stations';
import { Song, Station } from '@/types/station';

function mockDuration(song: Song): number {
  let h = 0;
  for (let i = 0; i < song.id.length; i++) h = (h * 31 + song.id.charCodeAt(i)) & 0xffff;
  return 180 + (h % 121);
}

interface Props {
  visible: boolean;
  station: Station;
  songIndex: number;
  isPlaying: boolean;
  onClose: () => void;
  onTogglePlay: () => void;
  onPrevSong: () => void;
  onNextSong: () => void;
  onSeek: (progress: number) => void;
  progress: number;
  isFavorited: boolean;
  onToggleFavorite: () => void;
}

/** 全屏播放器 — 封面占满上半屏 + 透明背景控件 */
export function NowPlaying({
  visible, station, songIndex, isPlaying,
  onClose, onTogglePlay, onPrevSong, onNextSong, onSeek,
  progress, isFavorited, onToggleFavorite,
}: Props) {
  const { width: sw, height: sh } = useWindowDimensions();
  const translateY = useSharedValue(sh);

  const song = station.songs[songIndex] ?? { id: '0', title: station.title, artist: station.hostName };
  const duration = mockDuration(song);
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

      <View style={[styles.coverWrap, { marginTop: 18, marginBottom: 24 }]}>
        <View style={[styles.coverShadow, { width: coverW, height: coverH, borderRadius: 14, backgroundColor: color + '1A' }]} />
        <View style={[styles.cover, { width: coverW, height: coverH, borderRadius: 14 }]}>
          <LinearGradient
            colors={[color, color + 'CC', color + '88']}
            start={{ x: 0.25, y: 0 }}
            end={{ x: 0.75, y: 1 }}
            style={StyleSheet.absoluteFill}
          />
          <View style={[styles.cvHL, { width: coverW * 0.55, height: coverH * 0.28, borderRadius: coverW, top: coverH * 0.1 }]} />
        </View>
      </View>

      <View style={styles.lower}>
        <View style={styles.info}>
          <ThemedText style={styles.tag} numberOfLines={1} lightColor={AppleColors.tertiaryLabel} darkColor={AppleColors.tertiaryLabel}>
            {station.title}
          </ThemedText>
          <ThemedText style={styles.songTitle} numberOfLines={1} lightColor={AppleColors.label} darkColor={AppleColors.label}>
            {song.title}
          </ThemedText>
          <View style={styles.byRow}>
            <ThemedText style={styles.by} lightColor={AppleColors.secondaryLabel} darkColor={AppleColors.secondaryLabel}>
              by {song.artist}
            </ThemedText>
            <Pressable onPress={onToggleFavorite} hitSlop={8} style={({ pressed }) => [pressed && { opacity: 0.5 }]}>
              <IconSymbol size={16} name={isFavorited ? 'heart.fill' : 'heart'} color={isFavorited ? AppleColors.accent : AppleColors.tertiaryLabel} />
            </Pressable>
          </View>
        </View>

        <WaveformBar
          seed={songIndex * 100 + station.songs.length}
          progress={progress}
          duration={duration}
          onSeek={onSeek}
          marginH={COVER_MARGIN}
        />

        <View style={styles.controls}>
          <Pressable onPress={onPrevSong} hitSlop={14} style={({ pressed }) => [pressed && { opacity: 0.4 }]}>
            <IconSymbol size={36} name="backward.fill" color={AppleColors.label} />
          </Pressable>

          <Pressable onPress={onTogglePlay} hitSlop={16}>
            <IconSymbol
              size={52}
              name={isPlaying ? 'pause.fill' : 'play.fill'}
              color={AppleColors.label}
            />
          </Pressable>

          <Pressable onPress={onNextSong} hitSlop={14} style={({ pressed }) => [pressed && { opacity: 0.4 }]}>
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
  cvHL: { position: 'absolute', backgroundColor: 'rgba(255,255,255,0.08)', transform: [{ scaleY: 0.4 }], left: '22.5%' },
  lower: { flex: 1, justifyContent: 'space-evenly' },
  info: { alignItems: 'center', paddingHorizontal: 24 },
  tag: { ...AppleType.caption1, letterSpacing: 0.04, marginBottom: 6 },
  songTitle: { ...AppleType.title1, fontWeight: '500' as const, textAlign: 'center', letterSpacing: -0.01, marginBottom: 4 },
  byRow: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  by: { ...AppleType.subhead },
  controls: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-evenly', paddingHorizontal: 48 },
});
