#pragma once

// Test shim only: the production numeric headers are compiled unchanged.
#include <algorithm>
#include <cassert>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <limits>
#include <string>
#include <type_traits>

using uint = unsigned int;
using ulong = unsigned long;
using datetime = long;
using string = std::string;

template<class A, class B> auto MathMin(A a, B b) { return std::min<std::common_type_t<A,B>>(a,b); }
template<class A, class B> auto MathMax(A a, B b) { return std::max<std::common_type_t<A,B>>(a,b); }
template<class A> auto MathAbs(A a) { return std::abs(a); }
inline double MathSqrt(double x) { return std::sqrt(x); }
inline double MathPow(double x, double y) { return std::pow(x,y); }
inline double MathLog(double x) { return std::log(x); }
inline double MathFloor(double x) { return std::floor(x); }
inline double MathCeil(double x) { return std::ceil(x); }
inline double MathRound(double x) { return std::round(x); }
inline bool MathIsValidNumber(double x) { return std::isfinite(x); }
template<class T> void ZeroMemory(T &value) { std::memset(&value,0,sizeof(value)); }
