import React, { useState } from 'react';
import { View, StyleSheet } from 'react-native';
import { StatusBar } from 'expo-status-bar';
import { SafeAreaProvider } from 'react-native-safe-area-context';

import RadioScreen from './src/screens/RadioScreen';
import DiscoverScreen from './src/screens/DiscoverScreen';
import MineScreen from './src/screens/MineScreen';
import SettingsScreen from './src/screens/SettingsScreen';
import MiniPlayer from './src/components/player/MiniPlayer';
import BottomTabBar, { TabKey } from './src/components/navigation/BottomTabBar';
import { mockUserProfile, UserProfile } from './src/data/mockData';

type ViewState = 'main' | 'settings';

export default function App() {
  const [activeTab, setActiveTab] = useState<TabKey>('mine');
  const [view, setView] = useState<ViewState>('main');
  const [profile, setProfile] = useState<UserProfile>(mockUserProfile);

  // Settings takes over the full screen
  if (view === 'settings') {
    return (
      <SafeAreaProvider>
        <StatusBar style="light" />
        <SettingsScreen
          profile={profile}
          onBack={() => setView('main')}
          onSaveProfile={setProfile}
          onSaveAndBackToMine={() => setView('main')}
        />
      </SafeAreaProvider>
    );
  }

  // Main layout with tabs + mini player
  return (
    <SafeAreaProvider>
      <StatusBar style="light" />
      <View style={styles.root}>
        {/* Content Area */}
        <View style={styles.content}>
          {activeTab === 'radio' && <RadioScreen />}
          {activeTab === 'discover' && <DiscoverScreen />}
          {activeTab === 'mine' && (
            <MineScreen
              profile={profile}
              onNavigateToSettings={() => setView('settings')}
            />
          )}
        </View>

        {/* Mini Player — above tab bar */}
        <MiniPlayer
          station={profile.nowPlaying}
          artist="Unknown Artist"
        />

        {/* Bottom Tab Bar */}
        <BottomTabBar activeTab={activeTab} onTabPress={setActiveTab} />
      </View>
    </SafeAreaProvider>
  );
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
    backgroundColor: '#121212',
  },
  content: {
    flex: 1,
  },
});
