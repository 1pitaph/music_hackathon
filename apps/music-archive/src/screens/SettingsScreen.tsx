import React from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  ScrollView,
  Platform,
} from 'react-native';

interface SettingsScreenProps {
  onBack: () => void;
}

export default function SettingsScreen({ onBack }: SettingsScreenProps) {
  return (
    <View style={styles.root}>
      {/* Header */}
      <View style={styles.header}>
        <TouchableOpacity onPress={onBack} style={styles.backBtn} activeOpacity={0.7}>
          <Text style={styles.backIcon}>&#8592;</Text>
        </TouchableOpacity>
        <Text style={styles.headerTitle}>设置</Text>
        <View style={styles.headerSpacer} />
      </View>

      {/* Content */}
      <ScrollView
        style={styles.scrollView}
        contentContainerStyle={styles.scrollContent}
        showsVerticalScrollIndicator={false}
      >
        {/* 占位：Apple Music 授权管理 */}
        <View style={styles.card}>
          <Text style={styles.cardTitle}>Apple Music 授权</Text>
          <Text style={styles.cardHint}>管理 Apple Music 授权状态（即将上线）</Text>
        </View>

        {/* 占位：数据收集 */}
        <View style={styles.card}>
          <Text style={styles.cardTitle}>数据收集</Text>
          <Text style={styles.cardHint}>管理听歌数据收集偏好（即将上线）</Text>
        </View>

        {/* 占位：档案设置 */}
        <View style={styles.card}>
          <Text style={styles.cardTitle}>档案设置</Text>
          <Text style={styles.cardHint}>编辑个人档案信息（即将上线）</Text>
        </View>

        {/* 占位：关于 */}
        <View style={styles.card}>
          <Text style={styles.cardTitle}>关于</Text>
          <Text style={styles.cardHint}>音乐档案 v1.0.0</Text>
        </View>
      </ScrollView>
    </View>
  );
}

const HEADER_BG = '#1e1b4b';

const styles = StyleSheet.create({
  root: {
    flex: 1,
    backgroundColor: '#f3f4f6',
  },

  /* ---- Header ---- */
  header: {
    backgroundColor: HEADER_BG,
    flexDirection: 'row',
    alignItems: 'center',
    paddingTop: Platform.OS === 'ios' ? 60 : 44,
    paddingBottom: 16,
    paddingHorizontal: 16,
    borderBottomLeftRadius: 24,
    borderBottomRightRadius: 24,
  },
  backBtn: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: 'rgba(255,255,255,0.15)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  backIcon: {
    fontSize: 20,
    color: '#fff',
  },
  headerTitle: {
    flex: 1,
    textAlign: 'center',
    color: '#fff',
    fontSize: 18,
    fontWeight: '600',
    marginRight: 36, // offset to center against back button
  },
  headerSpacer: {
    width: 36,
  },

  /* ---- Content ---- */
  scrollView: {
    flex: 1,
  },
  scrollContent: {
    padding: 16,
  },

  /* ---- Card ---- */
  card: {
    backgroundColor: '#fff',
    borderRadius: 16,
    padding: 16,
    marginBottom: 12,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.06,
    shadowRadius: 8,
    elevation: 2,
  },
  cardTitle: {
    fontSize: 17,
    fontWeight: '600',
    color: '#1f2937',
    marginBottom: 4,
  },
  cardHint: {
    fontSize: 14,
    color: '#9ca3af',
  },
});
