import React, { useState } from 'react';
import {
  View,
  Text,
  TextInput,
  Image,
  TouchableOpacity,
  ScrollView,
  Alert,
  StyleSheet,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import * as ImagePicker from 'expo-image-picker';
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
  const [bio, setBio] = useState(profile.bio);
  const [selectedColor, setSelectedColor] = useState(profile.avatarColor);
  const [avatarSource, setAvatarSource] = useState<any>(profile.avatarImage);
  const [avatarFailed, setAvatarFailed] = useState(false);

  const handlePickAvatar = async () => {
    const { status } = await ImagePicker.requestMediaLibraryPermissionsAsync();
    if (status !== 'granted') {
      Alert.alert('需要相册权限', '请在系统设置中允许访问相册后重试');
      return;
    }

    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ['images'],
      allowsEditing: true,
      aspect: [1, 1],
      quality: 0.8,
    });

    if (!result.canceled && result.assets.length > 0) {
      setAvatarSource({ uri: result.assets[0].uri });
      setAvatarFailed(false);
    }
  };

  const handleSave = () => {
    onSave({
      ...profile,
      nickname,
      bio,
      avatarColor: selectedColor,
      avatarImage: avatarSource,
    });
    onSaveAndBackToMine();
  };

  return (
    <SafeAreaView style={styles.safe}>
      <SettingsHeader title="" onBack={onBack} />
      <ScrollView
        style={styles.scroll}
        contentContainerStyle={styles.content}
        showsVerticalScrollIndicator={false}
        keyboardShouldPersistTaps="handled"
      >
        {/* Avatar Preview + Upload */}
        <Text style={styles.label}>头像图片</Text>
        <View style={styles.avatarRow}>
          <View
            style={[
              styles.avatarPreview,
              { backgroundColor: avatarFailed || !avatarSource ? selectedColor : 'transparent' },
            ]}
          >
            {avatarSource && !avatarFailed ? (
              <Image
                source={avatarSource}
                style={styles.avatarPreviewImage}
                onError={() => setAvatarFailed(true)}
                resizeMode="cover"
              />
            ) : (
              <Text style={styles.avatarPreviewText}>
                {nickname.charAt(0) || profile.nickname.charAt(0)}
              </Text>
            )}
          </View>
          <TouchableOpacity
            style={styles.pickButton}
            onPress={handlePickAvatar}
            activeOpacity={0.7}
          >
            <Text style={styles.pickButtonText}>更换头像</Text>
          </TouchableOpacity>
        </View>

        <Text style={[styles.label, styles.fieldGap]}>昵称</Text>
        <TextInput
          style={styles.input}
          value={nickname}
          onChangeText={setNickname}
          placeholder="输入昵称"
          placeholderTextColor="rgba(255,255,255,0.3)"
          maxLength={20}
          autoFocus
        />

        <Text style={[styles.label, styles.fieldGap]}>电台简介</Text>
        <TextInput
          style={styles.input}
          value={bio}
          onChangeText={setBio}
          placeholder="输入电台简介"
          placeholderTextColor="rgba(255,255,255,0.3)"
          maxLength={60}
        />

        <Text style={[styles.label, styles.fieldGap]}>头像颜色（无图片时作为头像底色）</Text>
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

  /* ---- Avatar ---- */
  label: {
    color: 'rgba(255,255,255,0.6)',
    fontSize: 14,
    fontWeight: '500',
    marginBottom: 12,
  },
  avatarRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 20,
  },
  avatarPreview: {
    width: 80,
    height: 80,
    borderRadius: 40,
    justifyContent: 'center',
    alignItems: 'center',
    overflow: 'hidden',
  },
  avatarPreviewImage: {
    width: 80,
    height: 80,
    borderRadius: 40,
  },
  avatarPreviewText: {
    color: 'rgba(255,255,255,0.7)',
    fontSize: 28,
    fontWeight: '600',
  },
  pickButton: {
    paddingVertical: 10,
    paddingHorizontal: 20,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.25)',
  },
  pickButtonText: {
    color: 'rgba(255,255,255,0.8)',
    fontSize: 14,
    fontWeight: '500',
  },

  /* ---- Fields ---- */
  fieldGap: {
    marginTop: 32,
  },
  input: {
    color: '#fff',
    fontSize: 16,
    paddingVertical: 10,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: 'rgba(255,255,255,0.2)',
  },

  /* ---- Colors ---- */
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

  /* ---- Save ---- */
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
