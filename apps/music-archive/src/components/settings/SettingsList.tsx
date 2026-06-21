import React from 'react';
import {
  View,
  Text,
  ScrollView,
  TouchableOpacity,
  Alert,
  StyleSheet,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { SettingsListProps, SettingsPage } from './types';
import SettingsHeader from './SettingsHeader';

interface SettingsRow {
  key: SettingsPage | 'placeholder';
  label: string;
  hint?: string;
  disabled?: boolean;
}

interface SettingsSection {
  title: string;
  rows: SettingsRow[];
}

const SECTIONS: SettingsSection[] = [
  {
    title: '账号',
    rows: [
      { key: 'profile', label: '档案设置' },
      { key: 'appleMusic', label: 'Apple Music 授权' },
    ],
  },
  {
    title: '播放',
    rows: [
      { key: 'autoPlay', label: '自动播放下一个电台' },
      { key: 'placeholder', label: '后台播放', hint: '即将上线', disabled: true },
    ],
  },
  {
    title: '隐私',
    rows: [
      { key: 'stationVisibility', label: '电台可见性' },
      { key: 'placeholder', label: '收听记录公开', hint: '即将上线', disabled: true },
    ],
  },
  { title: '数据', rows: [{ key: 'dataCollection', label: '数据收集' }] },
  { title: '关于', rows: [{ key: 'about', label: '关于' }] },
];

export default function SettingsList({
  onBack,
  onNavigate,
  onLogout,
}: SettingsListProps) {
  const handleLogout = () => {
    Alert.alert('确认退出', '退出后需要重新登录', [
      { text: '取消', style: 'cancel' },
      { text: '退出', style: 'destructive', onPress: onLogout },
    ]);
  };

  return (
    <SafeAreaView style={styles.safe}>
      <SettingsHeader title="设置" onBack={onBack} />
      <ScrollView
        style={styles.scroll}
        contentContainerStyle={styles.scrollContent}
        showsVerticalScrollIndicator={false}
      >
        {SECTIONS.map((section, si) => {
          const isLastSection = si === SECTIONS.length - 1;
          return (
            <View key={section.title}>
              {/* Section header */}
              <Text style={styles.sectionTitle}>{section.title}</Text>

              {/* Section rows */}
              {section.rows.map((row, ri) => {
                const isLastRow = ri === section.rows.length - 1;
                return (
                  <View key={row.label}>
                    <TouchableOpacity
                      style={styles.row}
                      onPress={() =>
                        !row.disabled &&
                        onNavigate(row.key as SettingsPage)
                      }
                      activeOpacity={row.disabled ? 1 : 0.7}
                      disabled={row.disabled}
                    >
                      <Text
                        style={[
                          styles.rowLabel,
                          row.disabled && styles.rowLabelDisabled,
                        ]}
                      >
                        {row.label}
                      </Text>
                      <View style={styles.rowRight}>
                        {row.hint ? (
                          <Text style={styles.rowHint}>{row.hint}</Text>
                        ) : null}
                        {!row.disabled ? (
                          <Ionicons
                            name="chevron-forward"
                            size={18}
                            color="rgba(255,255,255,0.3)"
                          />
                        ) : null}
                      </View>
                    </TouchableOpacity>
                    {!isLastRow && <View style={styles.divider} />}
                  </View>
                );
              })}

              {/* Section spacing */}
              {!isLastSection && <View style={styles.sectionGap} />}
            </View>
          );
        })}

        {/* Logout */}
        <View style={styles.logoutArea}>
          <TouchableOpacity
            style={styles.logoutRow}
            onPress={handleLogout}
            activeOpacity={0.6}
          >
            <Text style={styles.logoutText}>退出登录</Text>
          </TouchableOpacity>
        </View>
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
    paddingBottom: 40,
  },

  /* ---- Section ---- */
  sectionTitle: {
    color: 'rgba(255,255,255,0.35)',
    fontSize: 12,
    fontWeight: '600',
    textTransform: 'uppercase',
    letterSpacing: 1,
    paddingTop: 28,
    paddingBottom: 8,
  },
  sectionGap: {
    height: 0,
  },

  /* ---- Row ---- */
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingVertical: 16,
  },
  rowLabel: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '500',
  },
  rowLabelDisabled: {
    color: 'rgba(255,255,255,0.45)',
  },
  rowRight: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  rowHint: {
    color: 'rgba(255,255,255,0.45)',
    fontSize: 14,
    marginRight: 6,
  },
  divider: {
    height: StyleSheet.hairlineWidth,
    backgroundColor: 'rgba(255,255,255,0.06)',
  },

  /* ---- Logout ---- */
  logoutArea: {
    marginTop: 36,
    alignItems: 'center',
  },
  logoutRow: {
    paddingVertical: 14,
    paddingHorizontal: 36,
  },
  logoutText: {
    color: '#e74c3c',
    fontSize: 15,
    fontWeight: '500',
  },
});
