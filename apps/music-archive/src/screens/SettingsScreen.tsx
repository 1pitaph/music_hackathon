import React, { useState } from 'react';
import { UserProfile } from '../data/mockData';
import { SettingsPage } from '../components/settings/types';
import SettingsList from '../components/settings/SettingsList';
import AboutPage from '../components/settings/AboutPage';
import DataCollectionPage from '../components/settings/DataCollectionPage';
import AppleMusicPage from '../components/settings/AppleMusicPage';
import ProfilePage from '../components/settings/ProfilePage';
import AutoPlayPage from '../components/settings/AutoPlayPage';
import StationVisibilityPage from '../components/settings/StationVisibilityPage';

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

  if (page === 'dataCollection') {
    return <DataCollectionPage onBack={() => setPage('list')} />;
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

  if (page === 'autoPlay') {
    return <AutoPlayPage onBack={() => setPage('list')} />;
  }

  if (page === 'stationVisibility') {
    return <StationVisibilityPage onBack={() => setPage('list')} />;
  }

  return (
    <SettingsList
      onBack={onBack}
      onNavigate={setPage}
      onLogout={() => {}}
    />
  );
}
