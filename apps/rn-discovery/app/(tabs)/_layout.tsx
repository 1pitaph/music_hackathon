import { Tabs } from 'expo-router';
import React from 'react';
import { Platform, StyleSheet } from 'react-native';

import { HapticTab } from '@/components/haptic-tab';
import { IconSymbol } from '@/components/ui/icon-symbol';
import { AppleColors } from '@/constants/theme';

/** iOS 原生感 Tab 栏 — 半透明 dark material + accent active */
export default function TabLayout() {
  return (
    <Tabs
      screenOptions={{
        headerShown: false,
        tabBarButton: HapticTab,
        tabBarActiveTintColor: AppleColors.accent,
        tabBarInactiveTintColor: AppleColors.quaternaryLabel,
        tabBarStyle: styles.bar,
        tabBarLabelStyle: styles.lb,
        tabBarIconStyle: styles.ic,
      }}
    >
      <Tabs.Screen name="radio"   options={{ title: '电台', tabBarIcon: ({ color }) => <IconSymbol size={27} name="antenna.radiowaves.left.and.right" color={color} /> }} />
      <Tabs.Screen name="index"   options={{ title: '发现', tabBarIcon: ({ color }) => <IconSymbol size={27} name="music.note.list" color={color} /> }} />
      <Tabs.Screen name="profile" options={{ title: '我的', tabBarIcon: ({ color }) => <IconSymbol size={27} name="person.crop.circle" color={color} /> }} />
    </Tabs>
  );
}

const styles = StyleSheet.create({
  bar: {
    backgroundColor: 'rgba(21,18,15,0.88)',
    borderTopColor: 'rgba(245,240,232,0.08)',
    borderTopWidth: StyleSheet.hairlineWidth,
    paddingTop: 8,
    height: Platform.OS === 'ios' ? 90 : 66,
  },
  lb: { fontSize: 11, letterSpacing: 0.02, marginTop: 2, fontWeight: '500' as const },
  ic: { marginBottom: -2 },
});
