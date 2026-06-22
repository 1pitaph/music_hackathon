import { Pressable, StyleSheet, View } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import Animated, { runOnJS, useAnimatedStyle, useSharedValue, withSequence, withSpring } from 'react-native-reanimated';

import { ThemedText } from '@/components/themed-text';
import { PlayPauseButton } from '@/components/PlayPauseButton';
import { AppleColors, AppleRadius, AppleType, Spacing } from '@/constants/theme';
import { FALLBACK_STATION, STATION_COLORS } from '@/data/stations';

const AP = Animated.createAnimatedComponent(Pressable);

interface Props { isPlaying: boolean; onPlayToggle: () => void; }

export function EmptyState({ isPlaying, onPlayToggle }: Props) {
  const sc = useSharedValue(1);
  const aS = useAnimatedStyle(() => ({ transform: [{ scale: sc.value }] }));
  const press = () => { sc.value = withSequence(withSpring(0.98, { damping: 14, stiffness: 400 }), withSpring(1, { damping: 10, stiffness: 300 })); runOnJS(onPlayToggle)(); };

  const c = STATION_COLORS[FALLBACK_STATION.id] ?? '#8C7355';

  return (
    <View style={styles.cd}>
      <AP style={[styles.art, aS]} onPress={press}>
        <LinearGradient colors={[c, c + 'CC', c + '99']} start={{ x: 0.2, y: 0 }} end={{ x: 0.8, y: 1 }} style={styles.gr} />
        <View style={styles.hl} />
      </AP>
      <View style={styles.bg}>
        <ThemedText style={styles.tt} lightColor={AppleColors.label} darkColor={AppleColors.label}>{FALLBACK_STATION.title}</ThemedText>
        <ThemedText style={styles.sh} lightColor={AppleColors.secondaryLabel} darkColor={AppleColors.secondaryLabel}>{FALLBACK_STATION.hostName}</ThemedText>
        <ThemedText style={styles.ds} lightColor={AppleColors.tertiaryLabel} darkColor={AppleColors.tertiaryLabel}>{FALLBACK_STATION.briefIntro}</ThemedText>
      </View>
      <View style={styles.pb}><PlayPauseButton isPlaying={isPlaying} onToggle={onPlayToggle} size={44} /></View>
    </View>
  );
}

const styles = StyleSheet.create({
  cd: { backgroundColor: AppleColors.surface, borderRadius: AppleRadius.card },
  art: { position: 'relative', height: 280, overflow: 'hidden', borderTopLeftRadius: AppleRadius.card, borderTopRightRadius: AppleRadius.card },
  gr: { ...StyleSheet.absoluteFillObject },
  hl: { position: 'absolute', top: 16, left: '20%', width: '60%', height: '50%', backgroundColor: 'rgba(255,255,255,0.06)', borderRadius: 999, transform: [{ scaleY: 0.4 }] },
  bg: { backgroundColor: AppleColors.surface, paddingTop: Spacing.xl, paddingHorizontal: Spacing.xl, paddingBottom: Spacing.lg },
  tt: { ...AppleType.title2 },
  sh: { ...AppleType.subhead },
  ds: { ...AppleType.footnote, marginTop: Spacing.sm },
  pb: { position: 'absolute', bottom: Spacing.lg, right: Spacing.xl },
});
