import React, { useState } from 'react';
import { StatusBar } from 'expo-status-bar';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import MineScreen from './src/screens/MineScreen';
import SettingsScreen from './src/screens/SettingsScreen';

type ViewState = 'mine' | 'settings';

export default function App() {
  const [view, setView] = useState<ViewState>('mine');

  if (view === 'settings') {
    return (
      <SafeAreaProvider>
        <StatusBar style="light" />
        <SettingsScreen onBack={() => setView('mine')} />
      </SafeAreaProvider>
    );
  }

  return (
    <SafeAreaProvider>
      <StatusBar style="light" />
      <MineScreen onNavigateToSettings={() => setView('settings')} />
    </SafeAreaProvider>
  );
}
