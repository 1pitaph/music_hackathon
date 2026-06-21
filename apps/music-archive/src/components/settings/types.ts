import { UserProfile } from '../../data/mockData';

export type SettingsPage =
  | 'list'
  | 'about'
  | 'dataCollection'
  | 'appleMusic'
  | 'profile'
  | 'autoPlay'
  | 'stationVisibility';

export interface SettingsSubPageProps {
  onBack: () => void;
}

export interface SettingsListProps {
  onBack: () => void;
  onNavigate: (page: SettingsPage) => void;
  onLogout: () => void;
}

export interface ProfilePageProps {
  profile: UserProfile;
  onBack: () => void;
  onSave: (profile: UserProfile) => void;
  onSaveAndBackToMine: () => void;
}
