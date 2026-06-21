import React, { useState, useCallback } from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  ActivityIndicator,
  StyleSheet,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { SettingsSubPageProps } from './types';
import SettingsHeader from './SettingsHeader';

type AuthState = 'unauthorized' | 'loading' | 'authorized';

export default function AppleMusicPage({ onBack }: SettingsSubPageProps) {
  const [authState, setAuthState] = useState<AuthState>('unauthorized');

  const handleConnect = useCallback(() => {
    setAuthState('loading');
    setTimeout(() => {
      setAuthState('authorized');
    }, 1500);
  }, []);

  return (
    <SafeAreaView style={styles.safe}>
      <SettingsHeader title="Apple Music 授权" onBack={onBack} />
      <View style={styles.content}>
        {authState === 'unauthorized' && (
          <>
            <Text style={styles.statusMuted}>未授权</Text>
            <TouchableOpacity
              style={styles.button}
              onPress={handleConnect}
              activeOpacity={0.8}
            >
              <Text style={styles.buttonText}>连接 Apple Music</Text>
            </TouchableOpacity>
          </>
        )}

        {authState === 'loading' && (
          <>
            <ActivityIndicator color="#fff" size="small" />
            <Text style={styles.statusLoading}>连接中…</Text>
          </>
        )}

        {authState === 'authorized' && (
          <>
            <Text style={styles.statusActive}>已授权</Text>
            <View style={styles.infoCard}>
              <Text style={styles.infoLabel}>Apple ID</Text>
              <Text style={styles.infoValue}>user@icloud.com</Text>
            </View>
            <View style={styles.infoCard}>
              <Text style={styles.infoLabel}>订阅</Text>
              <Text style={styles.infoValue}>Apple Music 个人版</Text>
            </View>
          </>
        )}
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
    paddingHorizontal: 20,
    paddingTop: 32,
    alignItems: 'center',
  },
  statusMuted: {
    color: 'rgba(255,255,255,0.45)',
    fontSize: 14,
    marginBottom: 24,
  },
  statusLoading: {
    color: 'rgba(255,255,255,0.45)',
    fontSize: 14,
    marginTop: 16,
  },
  statusActive: {
    color: '#00d4aa',
    fontSize: 14,
    fontWeight: '600',
    marginBottom: 32,
  },
  button: {
    width: '100%',
    backgroundColor: '#fff',
    borderRadius: 8,
    paddingVertical: 14,
    alignItems: 'center',
  },
  buttonText: {
    color: '#121212',
    fontSize: 16,
    fontWeight: '600',
  },
  infoCard: {
    width: '100%',
    paddingVertical: 16,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: 'rgba(255,255,255,0.06)',
  },
  infoLabel: {
    color: 'rgba(255,255,255,0.45)',
    fontSize: 13,
    marginBottom: 4,
  },
  infoValue: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '500',
  },
});
