import { StyleSheet, View } from 'react-native';
import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import { AppleColors, AppleType, Spacing } from '@/constants/theme';

export default function RadioScreen() {
  return (
    <ThemedView style={styles.root} lightColor={AppleColors.background} darkColor={AppleColors.background}>
      <View style={styles.center}>
        <ThemedText style={styles.label} lightColor={AppleColors.tertiaryLabel} darkColor={AppleColors.tertiaryLabel}>
          电台
        </ThemedText>
      </View>
    </ThemedView>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  center: {},
  label: { ...AppleType.title2 },
});
