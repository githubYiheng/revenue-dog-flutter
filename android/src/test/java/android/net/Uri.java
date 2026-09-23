package android.net;

/**
 * **仅测试**：纯 JVM 单测里 android.jar 的 {@code Uri} 是 stub（{@code Uri.parse} 返回 null / 抛 "not mocked"），
 * 而原生 {@code CustomerInfoFactory} 用 {@code Uri.parse} 解析 {@code management_url}。
 * 测试类目录在 test runtime classpath 上先于 android.jar，本替身因此生效，只保留 Bridge 用到的
 * {@code parse} / {@code toString}（语义 = 原串往返，与真机 {@code Uri.toString()} 对这类绝对 URL 一致）。
 * 不用 Robolectric：brief 要求 Bridge 测试保持纯 JVM。
 */
public class Uri {

    private final String value;

    private Uri(String value) {
        this.value = value;
    }

    public static Uri parse(String uriString) {
        if (uriString == null) {
            throw new NullPointerException("uriString");
        }
        return new Uri(uriString);
    }

    @Override
    public String toString() {
        return value;
    }

    @Override
    public boolean equals(Object other) {
        return other instanceof Uri && ((Uri) other).value.equals(value);
    }

    @Override
    public int hashCode() {
        return value.hashCode();
    }
}
