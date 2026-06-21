import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { SettingsSubPageProps } from './types';
import SettingsHeader from './SettingsHeader';

export default function ImportPlaylistPage({ onBack }: SettingsSubPageProps) {
  return (
    <SafeAreaView style={styles.safe}>
      <SettingsHeader title="导入播放列表" onBack={onBack} />
      <View style={styles.content}>
        <Text style={styles.hint}>Coming soon</Text>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: {
    flex: 1,
    backgroundColor: '#121212',
  },
  content: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 20,
  },
  hint: {
    color: 'rgba(255,255,255,0.3)',
    fontSize: 14,
  },
});
