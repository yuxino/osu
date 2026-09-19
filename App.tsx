import { useEffect } from 'react';
import { StatusBar } from 'expo-status-bar';
import { NativeModules, Platform, Pressable, StyleSheet, Text, View } from 'react-native';

export default function App() {
  const available = Platform.OS === 'ios' && typeof NativeModules.MimiPrototype?.open === 'function';
  useEffect(() => {
    if (available) NativeModules.MimiPrototype.open();
  }, [available]);
  return (
    <View style={styles.container}>
      <Text style={styles.title}>Mimi</Text>
      <Text style={styles.description}>听懂此刻。</Text>
      <Pressable disabled={!available} accessibilityRole="button" onPress={() => NativeModules.MimiPrototype.open()} style={styles.button}>
        <Text style={styles.buttonText}>{available ? '打开字幕' : '请使用 iPhone 版本'}</Text>
      </Pressable>
      <StatusBar style="auto" />
    </View>
  );
}
const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#fff', paddingHorizontal: 30, justifyContent: 'center' },
  title: { fontSize: 42, fontWeight: '600', color: '#171717' },
  description: { fontSize: 20, lineHeight: 30, color: '#666', marginTop: 16, marginBottom: 36 },
  button: { backgroundColor: '#171717', borderRadius: 14, padding: 18, alignItems: 'center' },
  buttonText: { color: '#fff', fontSize: 16, fontWeight: '600' },
});
