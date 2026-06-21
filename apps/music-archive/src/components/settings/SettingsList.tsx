import React, { useState } from 'react';
import {
  View,
  Text,
  ScrollView,
  TouchableOpacity,
  Switch,
  Alert,
  StyleSheet,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { SettingsListProps, SettingsPage } from './types';
import SettingsHeader from './SettingsHeader';

type RowType = 'navigation' | 'switch' | 'status';

interface SettingsRow {
  key: string;
  label: string;
  type: RowType;
  hint?: string;
  defaultSwitchValue?: boolean;
  statusText?: string;
}

interface SettingsSection {
  title: string;
  rows: SettingsRow[];
}

export default function SettingsList({
  onBack,
  onNavigate,
  onLogout,
}: SettingsListProps) {
  // Inline switch states
  const [switches, setSwitches] = useState<Record<string, boolean>>({
    autoPlay: false,
    backgroundPlay: false,
    publicStation: false,
    dataCollection: true,
  });

  const toggleSwitch = (key: string) => {
    setSwitches((prev) => ({ ...prev, [key]: !prev[key] }));
  };

  const handleLogout = () => {
    Alert.alert('确认退出', '退出后需要重新登录', [
      { text: '取消', style: 'cancel' },
      { text: '退出', style: 'destructive', onPress: onLogout },
    ]);
  };

  const handlePress = (row: SettingsRow) => {
    if (row.key === 'privacyPolicy') {
      console.log('navigate to privacy policy');
      return;
    }
    if (row.key === 'termsOfService') {
      console.log('navigate to terms of service');
      return;
    }
    onNavigate(row.key as SettingsPage);
  };

  const SECTIONS: SettingsSection[] = [
    {
      title: '账号',
      rows: [
        { key: 'profile', label: '个人电台', type: 'navigation' },
        { key: 'appleMusic', label: 'Apple Music 授权', type: 'status', statusText: '未授权' },
      ],
    },
    {
      title: '播放',
      rows: [
        { key: 'autoPlay', label: '自动播放下一个电台', type: 'switch', defaultSwitchValue: false },
        { key: 'backgroundPlay', label: '后台播放', type: 'switch', defaultSwitchValue: false },
        { key: 'soundQuality', label: '音质', type: 'navigation' },
      ],
    },
    {
      title: '数据来源',
      rows: [
        { key: 'playHistory', label: '本App播放记录', type: 'navigation', hint: '342 小时' },
        { key: 'importPlaylist', label: '导入播放列表', type: 'navigation', hint: '3 个' },
        { key: 'manualAdd', label: '手动补充', type: 'navigation', hint: '12 条' },
      ],
    },
    {
      title: '隐私',
      rows: [
        { key: 'publicStation', label: '公开我的电台', type: 'switch', defaultSwitchValue: false },
        {
          key: 'dataCollection',
          label: '数据收集',
          type: 'switch',
          defaultSwitchValue: true,
          hint: '用于生成个人档案和电台推荐',
        },
      ],
    },
    {
      title: '关于',
      rows: [
        { key: 'about', label: '关于', type: 'navigation', hint: 'Music Archive v1.0.0' },
        { key: 'privacyPolicy', label: '隐私政策', type: 'navigation' },
        { key: 'termsOfService', label: '用户协议', type: 'navigation' },
      ],
    },
  ];

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
              <Text style={styles.sectionTitle}>{section.title}</Text>

              {section.rows.map((row, ri) => {
                const isLastRow = ri === section.rows.length - 1;

                // Switch row
                if (row.type === 'switch') {
                  const switchValue = switches[row.key] ?? row.defaultSwitchValue ?? false;
                  return (
                    <View key={row.key}>
                      <View style={styles.row}>
                        <View style={styles.rowTextArea}>
                          <Text style={styles.rowLabel}>{row.label}</Text>
                          {row.hint ? (
                            <Text style={styles.rowHint}>{row.hint}</Text>
                          ) : null}
                        </View>
                        <Switch
                          value={switchValue}
                          onValueChange={() => toggleSwitch(row.key)}
                          trackColor={{ false: '#3a3a3a', true: '#00d4aa' }}
                          thumbColor={switchValue ? '#fff' : '#888'}
                          ios_backgroundColor="#3a3a3a"
                        />
                      </View>
                      {!isLastRow && <View style={styles.divider} />}
                    </View>
                  );
                }

                // Status / Navigation row
                return (
                  <View key={row.key}>
                    <TouchableOpacity
                      style={styles.row}
                      onPress={() => handlePress(row)}
                      activeOpacity={0.7}
                    >
                      <View style={styles.rowTextArea}>
                        <Text style={styles.rowLabel}>{row.label}</Text>
                      </View>
                      <View style={styles.rowRight}>
                        {row.type === 'status' && row.statusText ? (
                          <Text style={styles.statusText}>{row.statusText}</Text>
                        ) : null}
                        {row.hint && row.type !== 'status' ? (
                          <Text style={styles.versionHint}>{row.hint}</Text>
                        ) : null}
                        <Ionicons
                          name="chevron-forward"
                          size={18}
                          color="rgba(255,255,255,0.3)"
                        />
                      </View>
                    </TouchableOpacity>
                    {!isLastRow && <View style={styles.divider} />}
                  </View>
                );
              })}

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
  rowTextArea: {
    flex: 1,
    marginRight: 12,
  },
  rowLabel: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '500',
  },
  rowHint: {
    color: 'rgba(255,255,255,0.4)',
    fontSize: 12,
    marginTop: 4,
    lineHeight: 16,
  },
  rowRight: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  statusText: {
    color: 'rgba(255,255,255,0.45)',
    fontSize: 14,
    marginRight: 4,
  },
  versionHint: {
    color: 'rgba(255,255,255,0.45)',
    fontSize: 14,
    marginRight: 4,
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
