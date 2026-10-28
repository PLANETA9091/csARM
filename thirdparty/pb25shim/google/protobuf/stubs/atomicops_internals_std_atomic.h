// csARM port: std::atomic-based AtomicOps for protobuf 2.5.0 on aarch64.
// protobuf 2.5.0 predates aarch64 and has no gcc internals for it; route all
// primitives through C++11 std::atomic which clang lowers to proper ARMv8
// ldaxr/stlxr sequences. Use <google/protobuf/stubs/atomicops.h> instead.

#ifndef GOOGLE_PROTOBUF_ATOMICOPS_INTERNALS_STD_ATOMIC_H_
#define GOOGLE_PROTOBUF_ATOMICOPS_INTERNALS_STD_ATOMIC_H_

#include <atomic>
#include <stdint.h>

namespace google {
namespace protobuf {
namespace internal {

inline std::atomic<Atomic32>* ToStd(volatile Atomic32* p) {
  return reinterpret_cast<std::atomic<Atomic32>*>(const_cast<Atomic32*>(p));
}
inline std::atomic<Atomic64>* ToStd(volatile Atomic64* p) {
  return reinterpret_cast<std::atomic<Atomic64>*>(const_cast<Atomic64*>(p));
}

inline void MemoryBarrier() {
  std::atomic_thread_fence(std::memory_order_seq_cst);
}

// ---------------- Atomic32 ----------------

inline Atomic32 NoBarrier_CompareAndSwap(volatile Atomic32* ptr,
                                         Atomic32 old_value,
                                         Atomic32 new_value) {
  Atomic32 expected = old_value;
  ToStd(ptr)->compare_exchange_strong(expected, new_value,
                                      std::memory_order_relaxed,
                                      std::memory_order_relaxed);
  return expected;  // previous value on CAS failure, old_value on success
}

inline Atomic32 NoBarrier_AtomicExchange(volatile Atomic32* ptr,
                                         Atomic32 new_value) {
  return ToStd(ptr)->exchange(new_value, std::memory_order_relaxed);
}

inline Atomic32 NoBarrier_AtomicIncrement(volatile Atomic32* ptr,
                                          Atomic32 increment) {
  return ToStd(ptr)->fetch_add(increment, std::memory_order_relaxed) + increment;
}

inline Atomic32 Barrier_AtomicIncrement(volatile Atomic32* ptr,
                                        Atomic32 increment) {
  return ToStd(ptr)->fetch_add(increment, std::memory_order_seq_cst) + increment;
}

inline Atomic32 Acquire_CompareAndSwap(volatile Atomic32* ptr,
                                       Atomic32 old_value,
                                       Atomic32 new_value) {
  Atomic32 expected = old_value;
  ToStd(ptr)->compare_exchange_strong(expected, new_value,
                                      std::memory_order_acquire,
                                      std::memory_order_acquire);
  return expected;
}

inline Atomic32 Release_CompareAndSwap(volatile Atomic32* ptr,
                                       Atomic32 old_value,
                                       Atomic32 new_value) {
  Atomic32 expected = old_value;
  ToStd(ptr)->compare_exchange_strong(expected, new_value,
                                      std::memory_order_release,
                                      std::memory_order_relaxed);
  return expected;
}

inline void NoBarrier_Store(volatile Atomic32* ptr, Atomic32 value) {
  ToStd(ptr)->store(value, std::memory_order_relaxed);
}
inline void Acquire_Store(volatile Atomic32* ptr, Atomic32 value) {
  ToStd(ptr)->store(value, std::memory_order_seq_cst);
}
inline void Release_Store(volatile Atomic32* ptr, Atomic32 value) {
  ToStd(ptr)->store(value, std::memory_order_release);
}
inline Atomic32 NoBarrier_Load(volatile const Atomic32* ptr) {
  return const_cast<std::atomic<Atomic32>*>(ToStd(ptr))->load(std::memory_order_relaxed);
}
inline Atomic32 Acquire_Load(volatile const Atomic32* ptr) {
  return const_cast<std::atomic<Atomic32>*>(ToStd(ptr))->load(std::memory_order_acquire);
}
inline Atomic32 Release_Load(volatile const Atomic32* ptr) {
  return const_cast<std::atomic<Atomic32>*>(ToStd(ptr))->load(std::memory_order_seq_cst);
}

// ---------------- Atomic64 ----------------

inline Atomic64 NoBarrier_CompareAndSwap(volatile Atomic64* ptr,
                                         Atomic64 old_value,
                                         Atomic64 new_value) {
  Atomic64 expected = old_value;
  ToStd(ptr)->compare_exchange_strong(expected, new_value,
                                      std::memory_order_relaxed,
                                      std::memory_order_relaxed);
  return expected;
}

inline Atomic64 NoBarrier_AtomicExchange(volatile Atomic64* ptr,
                                         Atomic64 new_value) {
  return ToStd(ptr)->exchange(new_value, std::memory_order_relaxed);
}

inline Atomic64 NoBarrier_AtomicIncrement(volatile Atomic64* ptr,
                                          Atomic64 increment) {
  return ToStd(ptr)->fetch_add(increment, std::memory_order_relaxed) + increment;
}

inline Atomic64 Barrier_AtomicIncrement(volatile Atomic64* ptr,
                                        Atomic64 increment) {
  return ToStd(ptr)->fetch_add(increment, std::memory_order_seq_cst) + increment;
}

inline Atomic64 Acquire_CompareAndSwap(volatile Atomic64* ptr,
                                       Atomic64 old_value,
                                       Atomic64 new_value) {
  Atomic64 expected = old_value;
  ToStd(ptr)->compare_exchange_strong(expected, new_value,
                                      std::memory_order_acquire,
                                      std::memory_order_acquire);
  return expected;
}

inline Atomic64 Release_CompareAndSwap(volatile Atomic64* ptr,
                                       Atomic64 old_value,
                                       Atomic64 new_value) {
  Atomic64 expected = old_value;
  ToStd(ptr)->compare_exchange_strong(expected, new_value,
                                      std::memory_order_release,
                                      std::memory_order_relaxed);
  return expected;
}

inline void NoBarrier_Store(volatile Atomic64* ptr, Atomic64 value) {
  ToStd(ptr)->store(value, std::memory_order_relaxed);
}
inline void Acquire_Store(volatile Atomic64* ptr, Atomic64 value) {
  ToStd(ptr)->store(value, std::memory_order_seq_cst);
}
inline void Release_Store(volatile Atomic64* ptr, Atomic64 value) {
  ToStd(ptr)->store(value, std::memory_order_release);
}
inline Atomic64 NoBarrier_Load(volatile const Atomic64* ptr) {
  return const_cast<std::atomic<Atomic64>*>(ToStd(ptr))->load(std::memory_order_relaxed);
}
inline Atomic64 Acquire_Load(volatile const Atomic64* ptr) {
  return const_cast<std::atomic<Atomic64>*>(ToStd(ptr))->load(std::memory_order_acquire);
}
inline Atomic64 Release_Load(volatile const Atomic64* ptr) {
  return const_cast<std::atomic<Atomic64>*>(ToStd(ptr))->load(std::memory_order_seq_cst);
}

}  // namespace internal
}  // namespace protobuf
}  // namespace google

#endif  // GOOGLE_PROTOBUF_ATOMICOPS_INTERNALS_STD_ATOMIC_H_
