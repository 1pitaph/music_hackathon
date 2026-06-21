import React, { useState } from 'react';
import { UserProfile } from '../data/mockData';
import { SettingsPage } from '../components/settings/types';
import SettingsList from '../components/settings/SettingsList';
import AboutPage from '../components/settings/AboutPage';
import AppleMusicPage from '../components/settings/AppleMusicPage';
import ProfilePage from '../components/settings/ProfilePage';
import SoundQualityPage from '../components/settings/SoundQualityPage';
import PlayHistoryPage from '../components/settings/PlayHistoryPage';
import ImportPlaylistPage from '../components/settings/ImportPlaylistPage';
import ManualAddPage from '../components/settings/ManualAddPage';

interface SettingsScreenProps {
  profile: UserProfile;
  onBack: () => void;
  onSaveProfile: (profile: UserProfile) => void;
  onSaveAndBackToMine: () => void;
}

export default function SettingsScreen({
  profile,
  onBack,
  onSaveProfile,
  onSaveAndBackToMine,
}: SettingsScreenProps) {
  const [page, setPage] = useState<SettingsPage>('list');

  if (page === 'about') {
    return <AboutPage onBack={() => setPage('list')} />;
  }

  if (page === 'appleMusic') {
    return <AppleMusicPage onBack={() => setPage('list')} />;
  }

  if (page === 'profile') {
    return (
      <ProfilePage
        profile={profile}
        onBack={() => setPage('list')}
        onSave={onSaveProfile}
        onSaveAndBackToMine={onSaveAndBackToMine}
      />
    );
  }

  if (page === 'soundQuality') {
    return <SoundQualityPage onBack={() => setPage('list')} />;
  }

  if (page === 'playHistory') {
    return <PlayHistoryPage onBack={() => setPage('list')} />;
  }

  if (page === 'importPlaylist') {
    return <ImportPlaylistPage onBack={() => setPage('list')} />;
  }

  if (page === 'manualAdd') {
    return <ManualAddPage onBack={() => setPage('list')} />;
  }

  return (
    <SettingsList
      onBack={onBack}
      onNavigate={setPage}
      onLogout={() => {}}
    />
  );
}
