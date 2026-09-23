import {subtitleV2Validation as v} from './subtitleV2Validation';
describe('Subtitle v2 contract',()=>{
 const row=(start=1,end=3)=>({start,end,original:'hello world',words:[{text:'hello',start:1,end:2},{text:'world',start:2,end:3}]});
 it('preserves original and acoustic word timestamps',()=>{
  const doc=v.original({language:'en',segments:[row()]},10,'id');
  expect(doc.segments[0].words.length).toBe(2);expect(doc.segments[0].original).toBe('hello world');
 });
 it('never invents word timing when incomplete',()=>{
  const doc=v.original({language:'en',segments:[{...row(),words:[{text:'hello',start:1,end:2}]}]},10,'id');
  expect(doc.segments[0].words).toEqual([]);expect(doc.segments[0].timing).toBe('phrase');
 });
 it('sorts and rejects overlaps and invalid ranges',()=>{
  const doc=v.original({language:'en',segments:[row(4,5),row(),row(2,4),row(-1,0),row(8,20),row(NaN,9)]},10,'id');
  expect(doc.segments.map(s=>s.start)).toEqual([1,4]);
 });
 it('keeps real silence as a gap',()=>{
  const doc=v.original({language:'ar',segments:[{...row(),original:'مرحبا',words:[]},{...row(6,8),original:'بكم',words:[]}]},10,'id');
  expect(doc.segments[1].start).toBe(6);expect(doc.segments[0].end).toBe(3);
 });
 it('rejects empty speech and incomplete translations',()=>{
  expect(()=>v.original({language:'en',segments:[]},10,'id')).toThrow();
  const doc=v.original({language:'en',segments:[row()]},10,'id');
  expect(()=>v.translation({segments:[]},doc)).toThrow();
  expect(()=>v.translation({segments:[{id:'s0',text:'a'},{id:'s0',text:'b'}]},doc)).toThrow();
  expect(v.translation({segments:[{id:'s0',text:'Привет, мир'}]},doc)).toEqual({s0:'Привет, мир'});
  expect(doc.segments[0].original).toBe('hello world');
 });
});
