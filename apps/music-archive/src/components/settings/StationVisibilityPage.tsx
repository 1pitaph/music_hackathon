import React, { useState } from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  ScrollView,
  StyleSheet,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { SettingsSubPageProps } from './types';
import SettingsHeader from './SettingsHeader';

const OPTIONS = [
  { value: 'public', label: '所有人可见', description: '任何人都可以找到并收听你的电台' },
  { value: 'friends', label: '仅好友可见', description: '只有你的好友可以找到你的电台' },
  { value: 'private', label: '仅自己可见', description: '只有你自己可以看到你的电台' },
] as const;

export default function StationVisibilityPage({ onBack }: SettingsSubPageProps) {
  const [selected, setSelected] = useState<string>('public');

  return (
    <SafeAreaView style={styles.safe}>
      <SettingsHeader title="电台可见性" onBack={onBack} />
      <ScrollView
        style={styles.scroll}
        contentContainerStyle={styles.scrollContent}
        showsVerticalScrollIndicator={false}
      >
        {OPTIONS.map((opt, i) => {
          const isSelected = selected === opt.value;
          return (
            <View key={opt.value}>
              {i > 0 && <View style={styles.divider} />}
              <TouchableOpacity
                style={styles.row}
                activeOpacity={0.5}
                onPress={() => setSelected(opt.value)}
              >
                <View style={styles.rowText}>
                  <Text style={styles.rowLabel}>{opt.label}</Text>
                  <Text style={styles.rowDesc}>{opt.description}</Text>
                </View>
                {isSelected && (
                  <Ionicons
                    name="checkmark"
                    size={22}
                    color="#00d4aa"
                  />
                )}
              </TouchableOpacity>
            </View>
          );
        })}
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: {
    flex: 1,
    backgroundColor: '#121212',
  },
  scroll: {
    flex: 1,
  },
  scrollContent: {
    paddingHorizontal: 20,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 16,
  },
  rowText: {
    flex: 1,
    marginRight: 12,
  },
  rowLabel: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '500',
  },
  rowDesc: {
    color: 'rgba(255,255,255,0.4)',
    fontSize: 13,
    marginTop: 4,
    lineHeight: 18,
  },
  divider: {
    height: StyleSheet.hairlineWidth,
    backgroundColor: 'rgba(255,255,255,0.06)',
  },
});
