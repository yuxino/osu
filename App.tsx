import { StatusBar } from 'expo-status-bar';
import { NativeModules, Platform, Pressable, StyleSheet, Text, View } from 'react-native';

export default function App() {
  const available = Platform.OS === 'ios' && typeof NativeModules.MimiPrototype?.open === 'function';
  return (
    <View style={styles.container}>
      <Text style={styles.eyebrow}>OSU · EXPERIMENT 01</Text>
      <Text style={styles.title}>{'Mimi，\n来到手机上。'}</Text>
      <Text style={styles.description}>让其他 App 的英语声音，变成眼前的中文字幕。</Text>
      <Pressable disabled={!available} accessibilityRole="button" onPress={() => NativeModules.MimiPrototype.open()} style={({ pressed }) => [styles.button, pressed && styles.pressed, !available && styles.disabled]}>
        <Text style={styles.buttonText}>{available ? '打开真机实验' : '需要包含原生模块的 iPhone 安装包'}</Text>
      </Pressable>
      <Text style={styles.note}>设备本地处理 · 无需 API 密钥{ '\n' }实验阶段，暂不保证所有 App 兼容。</Text>
      <StatusBar style="dark" />
    </View>
  );
}
const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#fff', paddingHorizontal: 30, justifyContent: 'center' },
  eyebrow: { color: '#777', fontSize: 11, letterSpacing: 2, marginBottom: 24 },
  title: { fontSize: 40, lineHeight: 54, fontWeight: '700', color: '#171717' },
  description: { fontSize: 17, lineHeight: 28, color: '#666', marginTop: 20, marginBottom: 40 },
  button: { backgroundColor: '#171717', borderRadius: 14, padding: 18, alignItems: 'center' },
  buttonText: { color: '#fff', fontSize: 16, fontWeight: '600' },
  note: { color: '#888', fontSize: 12, lineHeight: 21, marginTop: 22 },
  pressed: { opacity: 0.7 }, disabled: { opacity: 0.45 },
});
