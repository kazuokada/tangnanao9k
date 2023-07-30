// 可変個のパラメータを受け取り、std::printf()関数の引数として転送する
// 第1パラメータは必須。
// 第1パラメータのうしろにカンマがあるので、第2パラメータも必須。
# define DEBUG_LOG(fmt, ...) sprintf(fmt, __VA_ARGS__);print(fmt)
