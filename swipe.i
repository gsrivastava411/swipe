/* Copyright (c) 2009-2011 Kyle Gorman
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to 
 * deal in the Software without restriction, including without limitation the 
 * rights to use, copy, modify, merge, publish, distribute, sublicense, and/or 
 * sell copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING 
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
 * IN THE SOFTWARE.
 *
 * swipe.i: SWIG file for python module
 */

%include "carrays.i"
%array_functions(double, doublea);

%module swipe %{
#define SWIG_FILE_WITH_INIT
#include "swipe.h"
%}

%pythoncode %{
import numpy as NP
from math import log, fsum, isnan
from bisect import bisect_left

## helper functions

def _mean(x):
    """ 
    Compute the mean of x
    """
    return fsum(x) / len(x)

def _var(x):
    """
    Compute the variance of x 
    """
    my_mean = mean(x)
    s = 0.
    for i in x:
        s += (i - my_mean) ** 2
    return s / len(x) - 1

def _regress(x, y):
    """
    Compute the intercept and slope for y ~ x
    """
    solution = NP.linalg.lstsq(NP.vstack((NP.ones(len(x)), x)).T, y)
    return solution[0]

## the class itself

class Swipe(object):
    """
    Wrapper class representing a SWIPE' p extraction
    """

    def __init__(self, path, pmin=100., pmax=600., st=.3, dt=0.001, mel=False):
        """
        Class constructor:

        path = either a file object pointing to a wav file, or a string path
        pmin = minimum frequency in Hz
        pmax = maximum frequency in Hz
        st = frequency cutoff (must be between [0.0, 1.0]
        dt = samplerate in seconds
        show_nan = if True, voiceless intervals are returned, marked as nan.
        """
        # Get Python path, just in case someone passed a file object
        f = path if isinstance(path, str) else path.name
        # Obtain the vector itself
        P = pyswipe(f, pmin, pmax, st, dt)
        # get function
        conv = None
        if mel: conv = lambda hz: 1127.01048 * log(1. + hz / 700.)
        else: conv = lambda hz: hz
        # generate
        tt = 0.
        self.t = []
        self.p = []
        if P.x < 1: 
            raise ValueError('Failed to read audio')
        for i in range(P.x):
            val = doublea_getitem(P.v, i)
            if not isnan(val):
                self.t.append(tt)
                self.p.append(conv(doublea_getitem(P.v, i)))
            tt += dt

    def __str__(self):
        return '<Swipe pitch track with %d points>' % len(self.t)

    def __len__(self):
        return len(self.t)

    def __iter__(self):
        return iter(zip(self.t, self.p))

    def __getitem__(self, t):
        """ 
        Takes a  argument and gives the nearest sample 
        """
        if self.t[0] <= 0.:
            raise ValueError, 'Time less than 0'
        i = bisect(self.t, t)
        if self.t[i] - t > t - self.t[i - 1]:
            return self.p[i - 1]
        else:
            return self.p[i]

    def _bisect(self, tmin=None, tmax=None):
        """ 
        Helper for bisection
        """
        if not tmin:
            if not tmax:
                raise ValueError, 'At least one of tmin, tmax must be defined'
            else:
                return (0, bisect(self.t, tmax))
        elif not tmax:
            return (bisect(self.t, tmin), len(self.t))
        else:
            return (bisect(self.t, tmin), bisect(self.t, tmax))

    def slice(self, tmin=None, tmax=None):
        """ 
        Slice out samples outside of s [tmin, tmax] inline 
        """
        if tmin or tmax:
            (i, j) = self._bisect(tmin, tmax)
            self.t = self.t[i:j]
            self.p = self.p[i:j]
        else:
            raise ValueError, 'At least one of tmin, tmax must be defined'

    def mean(self, tmin=None, tmax=None):
        """ 
        Return pitch mean 
        """
        if tmin or tmax:
            (i, j) = self._bisect(tmin, tmax)
            return mean(self.p[i:j])
        else:
            return mean(self.p)

    def var(self, tmin=None, tmax=None):
        """ 
        Return pitch variance 
        """
        if tmin or tmax:
            (i, j) = self._bisect(tmin, tmax)
            return var(self.p[i:j])
        else:
            return var(self.p)

    def sd(self, tmin=None, tmax=None):
        """ 
        Return pitch standard deviation 
        """
        return sqrt(self.var(tmin, tmax))

    def regress(self, tmin=None, tmax=None):
        """ 
        Return the linear regression intercept and slope for pitch ~ time. I
        wouldn't advise using this on raw p, but rather the Mel frequency 
        option: e.g., call Swipe(yourfilename, min, max, mel=True). The reason 
        for this is that Mel frequency is log-proportional to p in Hertz, 
        and I find log pitch is much closer to satisfying the normality 
        assumption.
        """
        if tmin or tmax:
            (i, j) = self._bisect(tmin, tmax)
            return _regress(self.t[i:j], self.p[i:j])
        else:
            return _regress(self.t, self.p)
%}

typedef struct { int x; double* v; } vector;
vector pyswipe(char wav[], double min, double max, double st, double dt);
