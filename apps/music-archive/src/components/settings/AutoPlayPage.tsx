import React, { useState } from 'react';
import { View, Text, Switch, StyleSheet } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { SettingsSubPageProps } from './types';
import SettingsHeader from './SettingsHeader';

export default function AutoPlayPage({ onBack }: SettingsSubPageProps) {
  const [enabled, setEnabled] = useState(false);

  return (
    <SafeAreaView style={styles.safe}>
      <SettingsHeader title="自动播放" onBack={onBack} />
      <View style={styles.row}>
        <Text style={styles.rowLabel}>自动播放下一个电台</Text>
        <Switch
          value={enabled}
          onValueChange={setEnabled}
          trackColor={{ false: '#3a3a3a', true: '#00d4aa' }}
          thumbColor={enabled ? '#fff' : '#888'}
          ios_backgroundColor="#3a3a3a"
        />
      </View>
      <Text style={styles.description}>
        当前电台结束后，自动播放推荐电台
      </Text>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: {
    flex: 1,
    backgroundColor: '#121212',
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 20,
    paddingVertical: 16,
  },
  rowLabel: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '500',
  },
  description: {
    color: 'rgba(255,255,255,0.45)',
    fontSize: 14,
    lineHeight: 20,
    paddingHorizontal: 20,
    marginTop: 12,
  },
});
