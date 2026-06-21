import React, { useState } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  ScrollView,
  StyleSheet,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { ProfilePageProps } from './types';
import SettingsHeader from './SettingsHeader';

const PRESET_COLORS = ['#2a2a2a', '#FF6B6B', '#4ECDC4', '#45B7D1', '#DDA0DD'];

export default function ProfilePage({
  profile,
  onBack,
  onSave,
  onSaveAndBackToMine,
}: ProfilePageProps) {
  const [nickname, setNickname] = useState(profile.nickname);
  const [selectedColor, setSelectedColor] = useState(profile.avatarColor);

  const handleSave = () => {
    onSave({ ...profile, nickname, avatarColor: selectedColor });
    onSaveAndBackToMine();
  };

  return (
    <SafeAreaView style={styles.safe}>
      <SettingsHeader title="档案设置" onBack={onBack} />
      <ScrollView
        style={styles.scroll}
        contentContainerStyle={styles.content}
        showsVerticalScrollIndicator={false}
        keyboardShouldPersistTaps="handled"
      >
        <Text style={styles.label}>昵称</Text>
        <TextInput
          style={styles.input}
          value={nickname}
          onChangeText={setNickname}
          placeholder="输入昵称"
          placeholderTextColor="rgba(255,255,255,0.3)"
          maxLength={20}
          autoFocus
        />

        <Text style={[styles.label, styles.colorLabel]}>头像颜色</Text>
        <View style={styles.colorGrid}>
          {PRESET_COLORS.map((color) => {
            const isSelected = selectedColor === color;
            return (
              <TouchableOpacity
                key={color}
                onPress={() => setSelectedColor(color)}
                activeOpacity={0.8}
                style={[
                  styles.colorBlock,
                  { backgroundColor: color },
                  isSelected && styles.colorBlockSelected,
                ]}
                accessibilityLabel={`选择颜色 ${color}`}
                accessibilityRole="radio"
                accessibilityState={{ checked: isSelected }}
              >
                {isSelected && <Text style={styles.checkmark}>✓</Text>}
              </TouchableOpacity>
            );
          })}
        </View>

        <TouchableOpacity
          style={styles.saveButton}
          onPress={handleSave}
          activeOpacity={0.8}
        >
          <Text style={styles.saveButtonText}>保存</Text>
        </TouchableOpacity>
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
  content: {
    paddingHorizontal: 20,
    paddingTop: 24,
    paddingBottom: 40,
  },
  label: {
    color: 'rgba(255,255,255,0.6)',
    fontSize: 14,
    fontWeight: '500',
    marginBottom: 12,
  },
  colorLabel: {
    marginTop: 32,
  },
  input: {
    color: '#fff',
    fontSize: 16,
    paddingVertical: 10,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: 'rgba(255,255,255,0.2)',
  },
  colorGrid: {
    flexDirection: 'row',
    gap: 16,
    flexWrap: 'wrap',
  },
  colorBlock: {
    width: 48,
    height: 48,
    borderRadius: 24,
    justifyContent: 'center',
    alignItems: 'center',
  },
  colorBlockSelected: {
    borderWidth: 3,
    borderColor: '#fff',
  },
  checkmark: {
    color: '#fff',
    fontSize: 18,
    fontWeight: '700',
  },
  saveButton: {
    marginTop: 48,
    backgroundColor: '#fff',
    borderRadius: 8,
    paddingVertical: 14,
    alignItems: 'center',
  },
  saveButtonText: {
    color: '#121212',
    fontSize: 16,
    fontWeight: '600',
  },
});
