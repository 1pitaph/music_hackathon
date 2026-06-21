import React, { useState } from 'react';
import { StatusBar } from 'expo-status-bar';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import MineScreen from './src/screens/MineScreen';
import SettingsScreen from './src/screens/SettingsScreen';
import { mockUserProfile, UserProfile } from './src/data/mockData';

type ViewState = 'mine' | 'settings';

export default function App() {
  const [view, setView] = useState<ViewState>('mine');
  const [profile, setProfile] = useState<UserProfile>(mockUserProfile);

  if (view === 'settings') {
    return (
      <SafeAreaProvider>
        <StatusBar style="light" />
        <SettingsScreen
          profile={profile}
          onBack={() => setView('mine')}
          onSaveProfile={setProfile}
          onSaveAndBackToMine={() => setView('mine')}
        />
      </SafeAreaProvider>
    );
  }

  return (
    <SafeAreaProvider>
      <StatusBar style="light" />
      <MineScreen
        profile={profile}
        onNavigateToSettings={() => setView('settings')}
      />
    </SafeAreaProvider>
  );
}
