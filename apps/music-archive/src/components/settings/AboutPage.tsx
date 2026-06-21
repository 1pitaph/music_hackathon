import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { SettingsSubPageProps } from './types';
import SettingsHeader from './SettingsHeader';

export default function AboutPage({ onBack }: SettingsSubPageProps) {
  return (
    <SafeAreaView style={styles.safe}>
      <SettingsHeader title="关于" onBack={onBack} />
      <View style={styles.content}>
        <Text style={styles.productName}>Music Radio</Text>
        <Text style={styles.version}>v1.0.0</Text>
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
  productName: {
    color: '#fff',
    fontSize: 24,
    fontWeight: '700',
  },
  version: {
    color: 'rgba(255,255,255,0.45)',
    fontSize: 15,
    marginTop: 8,
  },
});
