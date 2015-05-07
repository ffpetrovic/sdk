// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library test.src.task.driver_test;

import 'package:analyzer/src/context/cache.dart';
import 'package:analyzer/src/generated/engine.dart'
    show
        AnalysisContext,
        CacheState,
        InternalAnalysisContext,
        RetentionPriority;
import 'package:analyzer/src/generated/java_engine.dart';
import 'package:analyzer/src/generated/sdk_io.dart';
import 'package:analyzer/src/generated/source.dart';
import 'package:analyzer/src/generated/utilities_collection.dart';
import 'package:analyzer/src/task/model.dart';
import 'package:analyzer/task/model.dart';
import 'package:typed_mock/typed_mock.dart';
import 'package:unittest/unittest.dart';

import '../../generated/engine_test.dart';
import '../../generated/test_support.dart';
import '../../reflective_tests.dart';

main() {
  groupSep = ' | ';
  runReflectiveTests(AnalysisCacheTest);
  runReflectiveTests(CacheEntryTest);
  runReflectiveTests(CacheFlushManagerTest);
  runReflectiveTests(SdkCachePartitionTest);
  runReflectiveTests(UniversalCachePartitionTest);
  runReflectiveTests(ResultDataTest);
}

AnalysisCache createCache({AnalysisContext context,
    RetentionPriority policy: RetentionPriority.LOW}) {
  CachePartition partition = new UniversalCachePartition(context);
  return new AnalysisCache(<CachePartition>[partition]);
}

@reflectiveTest
class AnalysisCacheTest extends EngineTestCase {
  void test_creation() {
    expect(createCache(), isNotNull);
  }

  void test_get() {
    AnalysisCache cache = createCache();
    AnalysisTarget target = new TestSource();
    expect(cache.get(target), isNull);
  }

  void test_getContextFor() {
    AnalysisContext context = new TestAnalysisContext();
    AnalysisCache cache = createCache(context: context);
    AnalysisTarget target = new TestSource();
    expect(cache.getContextFor(target), context);
  }

  void test_iterator() {
    AnalysisCache cache = createCache();
    AnalysisTarget target = new TestSource();
    CacheEntry entry = new CacheEntry();
    cache.put(target, entry);
    MapIterator<AnalysisTarget, CacheEntry> iterator = cache.iterator();
    expect(iterator.moveNext(), isTrue);
    expect(iterator.key, same(target));
    expect(iterator.value, same(entry));
    expect(iterator.moveNext(), isFalse);
  }

  void test_put() {
    AnalysisCache cache = createCache();
    AnalysisTarget target = new TestSource();
    CacheEntry entry = new CacheEntry();
    expect(cache.get(target), isNull);
    cache.put(target, entry);
    expect(cache.get(target), entry);
  }

  void test_remove() {
    AnalysisCache cache = createCache();
    AnalysisTarget target = new TestSource();
    cache.remove(target);
  }

  void test_size() {
    AnalysisCache cache = createCache();
    int size = 4;
    for (int i = 0; i < size; i++) {
      AnalysisTarget target = new TestSource("/test$i.dart");
      cache.put(target, new CacheEntry());
    }
    expect(cache.size(), size);
  }
}

@reflectiveTest
class CacheEntryTest extends EngineTestCase {
  InternalAnalysisContext context;
  AnalysisCache cache;

  void setUp() {
    context = new _InternalAnalysisContextMock();
    when(context.priorityTargets).thenReturn([]);
    cache = createCache(context: context);
    when(context.analysisCache).thenReturn(cache);
  }

  test_explicitlyAdded() {
    CacheEntry entry = new CacheEntry();
    expect(entry.explicitlyAdded, false);
    entry.explicitlyAdded = true;
    expect(entry.explicitlyAdded, true);
  }

  test_fixExceptionState_error_exception() {
    ResultDescriptor result = new ResultDescriptor('test', null);
    CaughtException exception = new CaughtException(null, null);
    CacheEntry entry = new CacheEntry();
    entry.setErrorState(exception, <ResultDescriptor>[result]);
    entry.fixExceptionState();
    expect(entry.getState(result), CacheState.ERROR);
    expect(entry.exception, exception);
  }

  test_fixExceptionState_noError_exception() {
    ResultDescriptor result = new ResultDescriptor('test', null);
    CacheEntry entry = new CacheEntry();
    // set one result to ERROR
    CaughtException exception = new CaughtException(null, null);
    entry.setErrorState(exception, <ResultDescriptor>[result]);
    // set the same result to VALID
    entry.setValue(result, 1, TargetedResult.EMPTY_LIST, null);
    // fix the exception state
    entry.fixExceptionState();
    expect(entry.exception, isNull);
  }

  test_fixExceptionState_noError_noException() {
    ResultDescriptor result = new ResultDescriptor('test', null);
    CacheEntry entry = new CacheEntry();
    entry.fixExceptionState();
    expect(entry.getState(result), CacheState.INVALID);
    expect(entry.exception, isNull);
  }

  test_getMemento_noResult() {
    String defaultValue = 'value';
    ResultDescriptor result = new ResultDescriptor('test', defaultValue);
    CacheEntry entry = new CacheEntry();
    expect(entry.getMemento(result), null);
  }

  test_getState() {
    ResultDescriptor result = new ResultDescriptor('test', null);
    CacheEntry entry = new CacheEntry();
    expect(entry.getState(result), CacheState.INVALID);
  }

  test_getValue() {
    String defaultValue = 'value';
    ResultDescriptor result = new ResultDescriptor('test', defaultValue);
    CacheEntry entry = new CacheEntry();
    expect(entry.getValue(result), defaultValue);
  }

  test_getValue_flushResults() {
    ResultCachingPolicy cachingPolicy = new SimpleResultCachingPolicy(2, 2);
    ResultDescriptor descriptor1 =
        new ResultDescriptor('result1', null, cachingPolicy: cachingPolicy);
    ResultDescriptor descriptor2 =
        new ResultDescriptor('result2', null, cachingPolicy: cachingPolicy);
    ResultDescriptor descriptor3 =
        new ResultDescriptor('result3', null, cachingPolicy: cachingPolicy);
    AnalysisTarget target = new TestSource();
    CacheEntry entry = new CacheEntry();
    cache.put(target, entry);
    {
      entry.setValue(descriptor1, 1, TargetedResult.EMPTY_LIST, null);
      expect(entry.getState(descriptor1), CacheState.VALID);
    }
    {
      entry.setValue(descriptor2, 2, TargetedResult.EMPTY_LIST, null);
      expect(entry.getState(descriptor1), CacheState.VALID);
      expect(entry.getState(descriptor2), CacheState.VALID);
    }
    // get descriptor1, so that descriptor2 will be flushed
    entry.getValue(descriptor1);
    {
      entry.setValue(descriptor3, 3, TargetedResult.EMPTY_LIST, null);
      expect(entry.getState(descriptor1), CacheState.VALID);
      expect(entry.getState(descriptor2), CacheState.FLUSHED);
      expect(entry.getState(descriptor3), CacheState.VALID);
    }
  }

  test_hasErrorState_false() {
    CacheEntry entry = new CacheEntry();
    expect(entry.hasErrorState(), false);
  }

  test_hasErrorState_true() {
    ResultDescriptor result = new ResultDescriptor('test', null);
    CaughtException exception = new CaughtException(null, null);
    CacheEntry entry = new CacheEntry();
    entry.setErrorState(exception, <ResultDescriptor>[result]);
    expect(entry.hasErrorState(), true);
  }

  test_invalidateAllInformation() {
    ResultDescriptor result = new ResultDescriptor('test', null);
    CacheEntry entry = new CacheEntry();
    entry.setValue(result, 'value', TargetedResult.EMPTY_LIST, null);
    entry.invalidateAllInformation();
    expect(entry.getState(result), CacheState.INVALID);
    expect(entry.getValue(result), isNull);
  }

  test_setErrorState() {
    ResultDescriptor result1 = new ResultDescriptor('res1', 1);
    ResultDescriptor result2 = new ResultDescriptor('res2', 2);
    ResultDescriptor result3 = new ResultDescriptor('res3', 3);
    // prepare some good state
    CacheEntry entry = new CacheEntry();
    entry.setValue(result1, 10, TargetedResult.EMPTY_LIST, null);
    entry.setValue(result2, 20, TargetedResult.EMPTY_LIST, null);
    entry.setValue(result3, 30, TargetedResult.EMPTY_LIST, null);
    // set error state
    CaughtException exception = new CaughtException(null, null);
    entry.setErrorState(exception, <ResultDescriptor>[result1, result2]);
    // verify
    expect(entry.exception, exception);
    expect(entry.getState(result1), CacheState.ERROR);
    expect(entry.getState(result2), CacheState.ERROR);
    expect(entry.getState(result3), CacheState.VALID);
    expect(entry.getValue(result1), 1);
    expect(entry.getValue(result2), 2);
    expect(entry.getValue(result3), 30);
  }

  test_setErrorState_invalidateDependent() {
    AnalysisTarget target1 = new TestSource('/a.dart');
    AnalysisTarget target2 = new TestSource('/b.dart');
    CacheEntry entry1 = new CacheEntry();
    CacheEntry entry2 = new CacheEntry();
    cache.put(target1, entry1);
    cache.put(target2, entry2);
    ResultDescriptor result1 = new ResultDescriptor('result1', -1);
    ResultDescriptor result2 = new ResultDescriptor('result2', -2);
    ResultDescriptor result3 = new ResultDescriptor('result3', -3);
    ResultDescriptor result4 = new ResultDescriptor('result4', -4);
    // set results, all of them are VALID
    entry1.setValue(result1, 111, TargetedResult.EMPTY_LIST, null);
    entry2.setValue(result2, 222, [new TargetedResult(target1, result1)], null);
    entry2.setValue(result3, 333, [new TargetedResult(target2, result2)], null);
    entry2.setValue(result4, 444, [], null);
    expect(entry1.getState(result1), CacheState.VALID);
    expect(entry2.getState(result2), CacheState.VALID);
    expect(entry2.getState(result3), CacheState.VALID);
    expect(entry2.getState(result4), CacheState.VALID);
    expect(entry1.getValue(result1), 111);
    expect(entry2.getValue(result2), 222);
    expect(entry2.getValue(result3), 333);
    expect(entry2.getValue(result4), 444);
    // set error state
    CaughtException exception = new CaughtException(null, null);
    entry1.setErrorState(exception, <ResultDescriptor>[result1]);
    // result2 and result3 are invalidated, result4 is intact
    expect(entry1.getState(result1), CacheState.ERROR);
    expect(entry2.getState(result2), CacheState.ERROR);
    expect(entry2.getState(result3), CacheState.ERROR);
    expect(entry2.getState(result4), CacheState.VALID);
    expect(entry1.getValue(result1), -1);
    expect(entry2.getValue(result2), -2);
    expect(entry2.getValue(result3), -3);
    expect(entry2.getValue(result4), 444);
    expect(entry1.exception, exception);
    expect(entry2.exception, exception);
  }

  test_setErrorState_noDescriptors() {
    CaughtException exception = new CaughtException(null, null);
    CacheEntry entry = new CacheEntry();
    expect(() {
      entry.setErrorState(exception, <ResultDescriptor>[]);
    }, throwsArgumentError);
  }

  test_setErrorState_noException() {
    ResultDescriptor result = new ResultDescriptor('test', null);
    CacheEntry entry = new CacheEntry();
    expect(() {
      entry.setErrorState(null, <ResultDescriptor>[result]);
    }, throwsArgumentError);
  }

  test_setErrorState_nullDescriptors() {
    CaughtException exception = new CaughtException(null, null);
    CacheEntry entry = new CacheEntry();
    expect(() {
      entry.setErrorState(exception, null);
    }, throwsArgumentError);
  }

  test_setState_error() {
    ResultDescriptor result = new ResultDescriptor('test', null);
    CacheEntry entry = new CacheEntry();
    entry.setValue(result, 42, TargetedResult.EMPTY_LIST, null);
    // an invalid state change
    expect(() {
      entry.setState(result, CacheState.ERROR);
    }, throwsArgumentError);
    // no changes
    expect(entry.getState(result), CacheState.VALID);
    expect(entry.getValue(result), 42);
  }

  test_setState_flushed() {
    ResultDescriptor result = new ResultDescriptor('test', 1);
    CacheEntry entry = new CacheEntry();
    // set VALID
    entry.setValue(result, 10, TargetedResult.EMPTY_LIST, null);
    expect(entry.getState(result), CacheState.VALID);
    expect(entry.getValue(result), 10);
    // set FLUSHED
    entry.setState(result, CacheState.FLUSHED);
    expect(entry.getState(result), CacheState.FLUSHED);
    expect(entry.getValue(result), 1);
  }

  test_setState_inProcess() {
    ResultDescriptor result = new ResultDescriptor('test', 1);
    CacheEntry entry = new CacheEntry();
    // set VALID
    entry.setValue(result, 10, TargetedResult.EMPTY_LIST, null);
    expect(entry.getState(result), CacheState.VALID);
    expect(entry.getValue(result), 10);
    // set IN_PROCESS
    entry.setState(result, CacheState.IN_PROCESS);
    expect(entry.getState(result), CacheState.IN_PROCESS);
    expect(entry.getValue(result), 10);
  }

  test_setState_invalid() {
    ResultDescriptor result = new ResultDescriptor('test', 1);
    CacheEntry entry = new CacheEntry();
    // set VALID
    String memento = 'main() {}';
    entry.setValue(result, 10, TargetedResult.EMPTY_LIST, memento);
    expect(entry.getState(result), CacheState.VALID);
    expect(entry.getValue(result), 10);
    // set INVALID
    entry.setState(result, CacheState.INVALID);
    expect(entry.getState(result), CacheState.INVALID);
    expect(entry.getValue(result), 1);
    expect(entry.getMemento(result), memento);
  }

  test_setState_invalid_invalidateDependent() {
    AnalysisTarget target = new TestSource();
    CacheEntry entry = new CacheEntry();
    cache.put(target, entry);
    ResultDescriptor result1 = new ResultDescriptor('result1', -1);
    ResultDescriptor result2 = new ResultDescriptor('result2', -2);
    ResultDescriptor result3 = new ResultDescriptor('result3', -3);
    ResultDescriptor result4 = new ResultDescriptor('result4', -4);
    // set results, all of them are VALID
    entry.setValue(result1, 111, TargetedResult.EMPTY_LIST, null);
    entry.setValue(result2, 222, [new TargetedResult(target, result1)], null);
    entry.setValue(result3, 333, [new TargetedResult(target, result2)], null);
    entry.setValue(result4, 444, [], null);
    expect(entry.getState(result1), CacheState.VALID);
    expect(entry.getState(result2), CacheState.VALID);
    expect(entry.getState(result3), CacheState.VALID);
    expect(entry.getState(result4), CacheState.VALID);
    expect(entry.getValue(result1), 111);
    expect(entry.getValue(result2), 222);
    expect(entry.getValue(result3), 333);
    expect(entry.getValue(result4), 444);
    // invalidate result1, invalidates result2 and result3, result4 is intact
    entry.setState(result1, CacheState.INVALID);
    expect(entry.getState(result1), CacheState.INVALID);
    expect(entry.getState(result2), CacheState.INVALID);
    expect(entry.getState(result3), CacheState.INVALID);
    expect(entry.getState(result4), CacheState.VALID);
    expect(entry.getValue(result1), -1);
    expect(entry.getValue(result2), -2);
    expect(entry.getValue(result3), -3);
    expect(entry.getValue(result4), 444);
  }

  test_setState_valid() {
    ResultDescriptor result = new ResultDescriptor('test', null);
    CacheEntry entry = new CacheEntry();
    expect(() => entry.setState(result, CacheState.VALID), throwsArgumentError);
  }

  test_setValue() {
    ResultDescriptor result = new ResultDescriptor('test', null);
    String value = 'value';
    String memento = 'main() {}';
    CacheEntry entry = new CacheEntry();
    entry.setValue(result, value, TargetedResult.EMPTY_LIST, memento);
    expect(entry.getState(result), CacheState.VALID);
    expect(entry.getValue(result), value);
    expect(entry.getMemento(result), memento);
  }

  test_setValue_flushResults() {
    ResultCachingPolicy cachingPolicy = new SimpleResultCachingPolicy(2, 2);
    ResultDescriptor descriptor1 =
        new ResultDescriptor('result1', null, cachingPolicy: cachingPolicy);
    ResultDescriptor descriptor2 =
        new ResultDescriptor('result2', null, cachingPolicy: cachingPolicy);
    ResultDescriptor descriptor3 =
        new ResultDescriptor('result3', null, cachingPolicy: cachingPolicy);
    AnalysisTarget target = new TestSource();
    CacheEntry entry = new CacheEntry();
    cache.put(target, entry);
    {
      entry.setValue(descriptor1, 1, TargetedResult.EMPTY_LIST, null);
      expect(entry.getState(descriptor1), CacheState.VALID);
    }
    {
      entry.setValue(descriptor2, 2, TargetedResult.EMPTY_LIST, null);
      expect(entry.getState(descriptor1), CacheState.VALID);
      expect(entry.getState(descriptor2), CacheState.VALID);
    }
    {
      entry.setValue(descriptor3, 3, TargetedResult.EMPTY_LIST, null);
      expect(entry.getState(descriptor1), CacheState.FLUSHED);
      expect(entry.getState(descriptor2), CacheState.VALID);
      expect(entry.getState(descriptor3), CacheState.VALID);
    }
  }

  test_setValue_invalidateDependent() {
    AnalysisTarget target = new TestSource();
    CacheEntry entry = new CacheEntry();
    cache.put(target, entry);
    ResultDescriptor result1 = new ResultDescriptor('result1', -1);
    ResultDescriptor result2 = new ResultDescriptor('result2', -2);
    ResultDescriptor result3 = new ResultDescriptor('result3', -3);
    ResultDescriptor result4 = new ResultDescriptor('result4', -4);
    // set results, all of them are VALID
    entry.setValue(result1, 111, TargetedResult.EMPTY_LIST, null);
    entry.setValue(result2, 222, [new TargetedResult(target, result1)], null);
    entry.setValue(result3, 333, [new TargetedResult(target, result2)], null);
    entry.setValue(result4, 444, [], null);
    expect(entry.getState(result1), CacheState.VALID);
    expect(entry.getState(result2), CacheState.VALID);
    expect(entry.getState(result3), CacheState.VALID);
    expect(entry.getState(result4), CacheState.VALID);
    expect(entry.getValue(result1), 111);
    expect(entry.getValue(result2), 222);
    expect(entry.getValue(result3), 333);
    expect(entry.getValue(result4), 444);
    // set result1, invalidates result2 and result3, result4 is intact
    entry.setValue(result1, 1111, TargetedResult.EMPTY_LIST, null);
    expect(entry.getState(result1), CacheState.VALID);
    expect(entry.getState(result2), CacheState.INVALID);
    expect(entry.getState(result3), CacheState.INVALID);
    expect(entry.getState(result4), CacheState.VALID);
    expect(entry.getValue(result1), 1111);
    expect(entry.getValue(result2), -2);
    expect(entry.getValue(result3), -3);
    expect(entry.getValue(result4), 444);
  }

  test_setValue_invalidateDependent2() {
    AnalysisTarget target1 = new TestSource('a');
    AnalysisTarget target2 = new TestSource('b');
    CacheEntry entry1 = new CacheEntry();
    CacheEntry entry2 = new CacheEntry();
    cache.put(target1, entry1);
    cache.put(target2, entry2);
    ResultDescriptor result1 = new ResultDescriptor('result1', -1);
    ResultDescriptor result2 = new ResultDescriptor('result2', -2);
    ResultDescriptor result3 = new ResultDescriptor('result3', -3);
    // set results, all of them are VALID
    entry1.setValue(result1, 111, TargetedResult.EMPTY_LIST, null);
    entry1.setValue(result2, 222, [new TargetedResult(target1, result1)], null);
    entry2.setValue(result3, 333, [new TargetedResult(target1, result2)], null);
    expect(entry1.getState(result1), CacheState.VALID);
    expect(entry1.getState(result2), CacheState.VALID);
    expect(entry2.getState(result3), CacheState.VALID);
    expect(entry1.getValue(result1), 111);
    expect(entry1.getValue(result2), 222);
    expect(entry2.getValue(result3), 333);
    // set result1, invalidates result2 and result3
    entry1.setValue(result1, 1111, TargetedResult.EMPTY_LIST, null);
    expect(entry1.getState(result1), CacheState.VALID);
    expect(entry1.getState(result2), CacheState.INVALID);
    expect(entry2.getState(result3), CacheState.INVALID);
    expect(entry1.getValue(result1), 1111);
    expect(entry1.getValue(result2), -2);
    expect(entry2.getValue(result3), -3);
  }

  test_toString_empty() {
    CacheEntry entry = new CacheEntry();
    expect(entry.toString(), isNotNull);
  }

  test_toString_nonEmpty() {
    String value = 'value';
    ResultDescriptor result = new ResultDescriptor('test', null);
    CacheEntry entry = new CacheEntry();
    entry.setValue(result, value, TargetedResult.EMPTY_LIST, null);
    expect(entry.toString(), isNotNull);
  }
}

@reflectiveTest
class CacheFlushManagerTest {
  CacheFlushManager manager = new CacheFlushManager(
      new SimpleResultCachingPolicy(15, 3), (AnalysisTarget target) => false);

  test_madeActive() {
    manager.madeActive();
    expect(manager.maxSize, 15);
  }

  test_madeIdle() {
    manager.madeActive();
    AnalysisTarget target = new TestSource();
    // prepare TargetedResult(s)
    List<TargetedResult> results = <TargetedResult>[];
    for (int i = 0; i < 15; i++) {
      ResultDescriptor descriptor = new ResultDescriptor('result$i', null);
      results.add(new TargetedResult(target, descriptor));
    }
    // notify about storing TargetedResult(s)
    for (TargetedResult result in results) {
      manager.resultStored(result, null);
    }
    expect(manager.recentlyUsed, results);
    expect(manager.currentSize, 15);
    // make idle
    List<TargetedResult> resultsToFlush = manager.madeIdle();
    expect(manager.maxSize, 3);
    expect(manager.recentlyUsed, results.skip(15 - 3));
    expect(resultsToFlush, results.take(15 - 3));
  }

  test_new() {
    expect(manager.maxActiveSize, 15);
    expect(manager.maxIdleSize, 3);
    expect(manager.maxSize, 3);
    expect(manager.currentSize, 0);
    expect(manager.recentlyUsed, isEmpty);
  }

  test_resultAccessed() {
    ResultDescriptor descriptor1 = new ResultDescriptor('result1', null);
    ResultDescriptor descriptor2 = new ResultDescriptor('result2', null);
    ResultDescriptor descriptor3 = new ResultDescriptor('result3', null);
    AnalysisTarget target = new TestSource();
    TargetedResult result1 = new TargetedResult(target, descriptor1);
    TargetedResult result2 = new TargetedResult(target, descriptor2);
    TargetedResult result3 = new TargetedResult(target, descriptor3);
    manager.resultStored(result1, null);
    manager.resultStored(result2, null);
    manager.resultStored(result3, null);
    expect(manager.currentSize, 3);
    expect(manager.recentlyUsed, orderedEquals([result1, result2, result3]));
    // access result2
    manager.resultAccessed(result2);
    expect(manager.currentSize, 3);
    expect(manager.recentlyUsed, orderedEquals([result1, result3, result2]));
  }

  test_resultAccessed_noSuchResult() {
    ResultDescriptor descriptor1 = new ResultDescriptor('result1', null);
    ResultDescriptor descriptor2 = new ResultDescriptor('result2', null);
    ResultDescriptor descriptor3 = new ResultDescriptor('result3', null);
    AnalysisTarget target = new TestSource();
    TargetedResult result1 = new TargetedResult(target, descriptor1);
    TargetedResult result2 = new TargetedResult(target, descriptor2);
    TargetedResult result3 = new TargetedResult(target, descriptor3);
    manager.resultStored(result1, null);
    manager.resultStored(result2, null);
    expect(manager.currentSize, 2);
    expect(manager.recentlyUsed, orderedEquals([result1, result2]));
    // access result3, no-op
    manager.resultAccessed(result3);
    expect(manager.currentSize, 2);
    expect(manager.recentlyUsed, orderedEquals([result1, result2]));
  }

  test_resultStored() {
    ResultDescriptor descriptor1 = new ResultDescriptor('result1', null);
    ResultDescriptor descriptor2 = new ResultDescriptor('result2', null);
    ResultDescriptor descriptor3 = new ResultDescriptor('result3', null);
    ResultDescriptor descriptor4 = new ResultDescriptor('result4', null);
    AnalysisTarget target = new TestSource();
    TargetedResult result1 = new TargetedResult(target, descriptor1);
    TargetedResult result2 = new TargetedResult(target, descriptor2);
    TargetedResult result3 = new TargetedResult(target, descriptor3);
    TargetedResult result4 = new TargetedResult(target, descriptor4);
    manager.resultStored(result1, null);
    manager.resultStored(result2, null);
    manager.resultStored(result3, null);
    expect(manager.currentSize, 3);
    expect(manager.recentlyUsed, orderedEquals([result1, result2, result3]));
    // store result2 again
    {
      List<TargetedResult> resultsToFlush = manager.resultStored(result2, null);
      expect(resultsToFlush, isEmpty);
      expect(manager.currentSize, 3);
      expect(manager.recentlyUsed, orderedEquals([result1, result3, result2]));
    }
    // store result4
    {
      List<TargetedResult> resultsToFlush = manager.resultStored(result4, null);
      expect(resultsToFlush, [result1]);
      expect(manager.currentSize, 3);
      expect(manager.recentlyUsed, orderedEquals([result3, result2, result4]));
      expect(manager.resultSizeMap, {result3: 1, result2: 1, result4: 1});
    }
  }

  test_targetRemoved() {
    ResultDescriptor descriptor1 = new ResultDescriptor('result1', null);
    ResultDescriptor descriptor2 = new ResultDescriptor('result2', null);
    ResultDescriptor descriptor3 = new ResultDescriptor('result3', null);
    AnalysisTarget target1 = new TestSource('a.dart');
    AnalysisTarget target2 = new TestSource('b.dart');
    TargetedResult result1 = new TargetedResult(target1, descriptor1);
    TargetedResult result2 = new TargetedResult(target2, descriptor2);
    TargetedResult result3 = new TargetedResult(target1, descriptor3);
    manager.resultStored(result1, null);
    manager.resultStored(result2, null);
    manager.resultStored(result3, null);
    expect(manager.currentSize, 3);
    expect(manager.recentlyUsed, orderedEquals([result1, result2, result3]));
    expect(manager.resultSizeMap, {result1: 1, result2: 1, result3: 1});
    // remove target1
    {
      manager.targetRemoved(target1);
      expect(manager.currentSize, 1);
      expect(manager.recentlyUsed, orderedEquals([result2]));
      expect(manager.resultSizeMap, {result2: 1});
    }
    // remove target2
    {
      manager.targetRemoved(target2);
      expect(manager.currentSize, 0);
      expect(manager.recentlyUsed, isEmpty);
      expect(manager.resultSizeMap, isEmpty);
    }
  }
}

abstract class CachePartitionTest extends EngineTestCase {
  CachePartition createPartition();

  void test_creation() {
    expect(createPartition(), isNotNull);
  }

  void test_entrySet() {
    CachePartition partition = createPartition();
    AnalysisTarget target = new TestSource();
    CacheEntry entry = new CacheEntry();
    partition.put(target, entry);
    Map<AnalysisTarget, CacheEntry> entryMap = partition.map;
    expect(entryMap, hasLength(1));
    AnalysisTarget entryKey = entryMap.keys.first;
    expect(entryKey, target);
    expect(entryMap[entryKey], entry);
  }

  void test_get() {
    CachePartition partition = createPartition();
    AnalysisTarget target = new TestSource();
    expect(partition.get(target), isNull);
  }

  void test_put_alreadyInPartition() {
    CachePartition partition1 = createPartition();
    CachePartition partition2 = createPartition();
    AnalysisTarget target = new TestSource();
    CacheEntry entry = new CacheEntry();
    partition1.put(target, entry);
    expect(() => partition2.put(target, entry), throwsStateError);
  }

  void test_put_noFlush() {
    CachePartition partition = createPartition();
    AnalysisTarget target = new TestSource();
    CacheEntry entry = new CacheEntry();
    partition.put(target, entry);
    expect(partition.get(target), entry);
  }

  void test_remove() {
    CachePartition partition = createPartition();
    AnalysisTarget target = new TestSource();
    CacheEntry entry = new CacheEntry();
    partition.put(target, entry);
    expect(partition.get(target), entry);
    partition.remove(target);
    expect(partition.get(target), isNull);
  }
}

@reflectiveTest
class ResultDataTest extends EngineTestCase {
  test_creation() {
    String value = 'value';
    ResultData data = new ResultData(new ResultDescriptor('test', value));
    expect(data, isNotNull);
    expect(data.state, CacheState.INVALID);
    expect(data.value, value);
  }
}

@reflectiveTest
class SdkCachePartitionTest extends CachePartitionTest {
  CachePartition createPartition() {
    return new SdkCachePartition(null);
  }

  void test_contains_false() {
    CachePartition partition = createPartition();
    AnalysisTarget target = new TestSource();
    expect(partition.contains(target), isFalse);
  }

  void test_contains_true() {
    SdkCachePartition partition = new SdkCachePartition(null);
    SourceFactory factory = new SourceFactory(
        [new DartUriResolver(DirectoryBasedDartSdk.defaultSdk)]);
    AnalysisTarget target = factory.forUri("dart:core");
    expect(partition.contains(target), isTrue);
  }
}

@reflectiveTest
class UniversalCachePartitionTest extends CachePartitionTest {
  CachePartition createPartition() {
    return new UniversalCachePartition(null);
  }

  void test_contains() {
    UniversalCachePartition partition = new UniversalCachePartition(null);
    TestSource source = new TestSource();
    expect(partition.contains(source), isTrue);
  }
}

class _InternalAnalysisContextMock extends TypedMock
    implements InternalAnalysisContext {
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
