# VecFunctionUnit

- Version: V2R2
- Status: OK
- Date: 2025/01/20
- commit：[xxx](https://github.com/OpenXiangShan/XiangShan/tree/xxx)

向量功能单元包括 vsetiwi, vsetiwf, vsetfwf, vipu, vialuF, vfpu, vldu, vstu, vppu, vimac,
vidiv, vfalu, vfma, vfdiv, vfcvt; 每个功能单元支持的指令如下表：

## vsetiwi vsetiwf vsetfwf

vsetiwi, vsetiwf, vsetfwf 这三个功能单元是用以支持 vset(VSETVLI, VSETIVLI, VSETVL) 指令 uop
拆分的，具体拆分方式请参考 decode 。

## vipu

table: vipu fu 支持的指令

| 功能单元 | 支持指令         | 扩展  | 描述     |
| ---- | ------------ | --- | ------ |
| vipu | vwredsumu.vs | V   | vector |
| vipu | vwredsum.vs  | V   | vector |
| vipu | vcpop.m      | V   | vector |
| vipu | vfirst.m     | V   | vector |
| vipu | vid.v        | V   | vector |
| vipu | viota.m      | V   | vector |
| vipu | vmsbf.vv     | V   | vector |
| vipu | vmsif.vv     | V   | vector |
| vipu | vmsof.vv     | V   | vector |
| vipu | vmv.x.s      | V   | vector |
| vipu | vredand.vs   | V   | vector |
| vipu | vredmax.vs   | V   | vector |
| vipu | vredmaxu.vs  | V   | vector |
| vipu | vredmin.vs   | V   | vector |
| vipu | vredminu.vs  | V   | vector |
| vipu | vredor.vs    | V   | vector |
| vipu | vredsum.vs   | V   | vector |
| vipu | vredxor.vs   | V   | vector |

## vialuF

table: vialuF fu 支持的指令

| 功能单元   | 支持指令         | 扩展  | 描述     |
| ------ | ------------ | --- | ------ |
| vialuF | vadd.vv      | V   | vector |
| vialuF | vsub.vv      | V   | vector |
| vialuF | vminu.vv     | V   | vector |
| vialuF | vmin.vv      | V   | vector |
| vialuF | vmaxu.vv     | V   | vector |
| vialuF | vmax.vv      | V   | vector |
| vialuF | vand.vv      | V   | vector |
| vialuF | vor.vv       | V   | vector |
| vialuF | vxor.vv      | V   | vector |
| vialuF | vadc.vvm     | V   | vector |
| vialuF | vmadc.vvm    | V   | vector |
| vialuF | vmadc.vv     | V   | vector |
| vialuF | vsbc.vvm     | V   | vector |
| vialuF | vmsbc.vv     | V   | vector |
| vialuF | vmsbc.vvm    | V   | vector |
| vialuF | vmerge.vvm   | V   | vector |
| vialuF | vmv.v.v      | V   | vector |
| vialuF | vmseq.vv     | V   | vector |
| vialuF | vmsne.vv     | V   | vector |
| vialuF | vmsltu.vv    | V   | vector |
| vialuF | vmslt.vv     | V   | vector |
| vialuF | vmsleu.vv    | V   | vector |
| vialuF | vmsle.vv     | V   | vector |
| vialuF | vsll.vv      | V   | vector |
| vialuF | vsrl.vv      | V   | vector |
| vialuF | vsra.vv      | V   | vector |
| vialuF | vnsrl.wv     | V   | vector |
| vialuF | vnsra.wv     | V   | vector |
| vialuF | vsaddu.vv    | V   | vector |
| vialuF | vsadd.vv     | V   | vector |
| vialuF | vssubu.vv    | V   | vector |
| vialuF | vssub.vv     | V   | vector |
| vialuF | vssrl.vv     | V   | vector |
| vialuF | vssra.vv     | V   | vector |
| vialuF | vnclipu.wv   | V   | vector |
| vialuF | vnclip.wv    | V   | vector |
| vialuF | vwredsumu.vs | V   | vector |
| vialuF | vwredsum.vs  | V   | vector |
| vialuF | vandn.vv     | V   | vector |
| vialuF | vrol.vv      | V   | vector |
| vialuF | vror.vv      | V   | vector |
| vialuF | vwsll.vv     | V   | vector |
| vialuF | vadd.vx      | V   | vector |
| vialuF | vsub.vx      | V   | vector |
| vialuF | vrsub.vx     | V   | vector |
| vialuF | vminu.vx     | V   | vector |
| vialuF | vmin.vx      | V   | vector |
| vialuF | vmaxu.vx     | V   | vector |
| vialuF | vmax.vx      | V   | vector |
| vialuF | vand.vx      | V   | vector |
| vialuF | vor.vx       | V   | vector |
| vialuF | vxor.vx      | V   | vector |
| vialuF | vadc.vxm     | V   | vector |
| vialuF | vmadc.vxm    | V   | vector |
| vialuF | vmadc.vx     | V   | vector |
| vialuF | vsbc.vxm     | V   | vector |
| vialuF | vmsbc.vx     | V   | vector |
| vialuF | vmsbc.vxm    | V   | vector |
| vialuF | vmerge.vxm   | V   | vector |
| vialuF | vmv.v.x      | V   | vector |
| vialuF | vmseq.vx     | V   | vector |
| vialuF | vmsne.vx     | V   | vector |
| vialuF | vmsltu.vx    | V   | vector |
| vialuF | vmslt.vx     | V   | vector |
| vialuF | vmsleu.vx    | V   | vector |
| vialuF | vmsle.vx     | V   | vector |
| vialuF | vmsgtu.vx    | V   | vector |
| vialuF | vmsgt.vx     | V   | vector |
| vialuF | vsll.vx      | V   | vector |
| vialuF | vsrl.vx      | V   | vector |
| vialuF | vsra.vx      | V   | vector |
| vialuF | vnsrl.wx     | V   | vector |
| vialuF | vnsra.wx     | V   | vector |
| vialuF | vsaddu.vx    | V   | vector |
| vialuF | vsadd.vx     | V   | vector |
| vialuF | vssubu.vx    | V   | vector |
| vialuF | vssub.vx     | V   | vector |
| vialuF | vssrl.vx     | V   | vector |
| vialuF | vssra.vx     | V   | vector |
| vialuF | vnclipu.wx   | V   | vector |
| vialuF | vnclip.wx    | V   | vector |
| vialuF | vandn.vx     | V   | vector |
| vialuF | vrol.vx      | V   | vector |
| vialuF | vror.vx      | V   | vector |
| vialuF | vwsll.vx     | V   | vector |
| vialuF | vadd.vi      | V   | vector |
| vialuF | vrsub.vi     | V   | vector |
| vialuF | vand.vi      | V   | vector |
| vialuF | vor.vi       | V   | vector |
| vialuF | vxor.vi      | V   | vector |
| vialuF | vadc.vim     | V   | vector |
| vialuF | vmadc.vim    | V   | vector |
| vialuF | vmadc.vi     | V   | vector |
| vialuF | vmerge.vim   | V   | vector |
| vialuF | vmv.v.i      | V   | vector |
| vialuF | vmseq.vi     | V   | vector |
| vialuF | vmsne.vi     | V   | vector |
| vialuF | vmsleu.vi    | V   | vector |
| vialuF | vmsle.vi     | V   | vector |
| vialuF | vmsgtu.vi    | V   | vector |
| vialuF | vmsgt.vi     | V   | vector |
| vialuF | vsll.vi      | V   | vector |
| vialuF | vsrl.vi      | V   | vector |
| vialuF | vsra.vi      | V   | vector |
| vialuF | vnsrl.wi     | V   | vector |
| vialuF | vnsra.wi     | V   | vector |
| vialuF | vsaddu.vi    | V   | vector |
| vialuF | vsadd.vi     | V   | vector |
| vialuF | vssrl.vi     | V   | vector |
| vialuF | vssra.vi     | V   | vector |
| vialuF | vnclipu.wi   | V   | vector |
| vialuF | vnclip.wi    | V   | vector |
| vialuF | vror.vi      | V   | vector |
| vialuF | vwsll.vi     | V   | vector |
| vialuF | vaadd.vv     | V   | vector |
| vialuF | vaaddu.vv    | V   | vector |
| vialuF | vasub.vv     | V   | vector |
| vialuF | vasubu.vv    | V   | vector |
| vialuF | vmand.mm     | V   | vector |
| vialuF | vmandn.mm    | V   | vector |
| vialuF | vmnand.mm    | V   | vector |
| vialuF | vmnor.mm     | V   | vector |
| vialuF | vmor.mm      | V   | vector |
| vialuF | vmorn.mm     | V   | vector |
| vialuF | vmxnor.mm    | V   | vector |
| vialuF | vmxor.mm     | V   | vector |
| vialuF | vsext.vf2    | V   | vector |
| vialuF | vsext.vf4    | V   | vector |
| vialuF | vsext.vf8    | V   | vector |
| vialuF | vzext.vf2    | V   | vector |
| vialuF | vzext.vf4    | V   | vector |
| vialuF | vzext.vf8    | V   | vector |
| vialuF | vwadd.vv     | V   | vector |
| vialuF | vwadd.wv     | V   | vector |
| vialuF | vwaddu.vv    | V   | vector |
| vialuF | vwaddu.wv    | V   | vector |
| vialuF | vwsub.vv     | V   | vector |
| vialuF | vwsub.wv     | V   | vector |
| vialuF | vwsubu.vv    | V   | vector |
| vialuF | vwsubu.wv    | V   | vector |
| vialuF | vbrev.v      | V   | vector |
| vialuF | vbrev8.v     | V   | vector |
| vialuF | vrev8.v      | V   | vector |
| vialuF | vclz.v       | V   | vector |
| vialuF | vctz.v       | V   | vector |
| vialuF | vcpop.v      | V   | vector |
| vialuF | vaadd.vx     | V   | vector |
| vialuF | vaaddu.vx    | V   | vector |
| vialuF | vasub.vx     | V   | vector |
| vialuF | vasubu.vx    | V   | vector |
| vialuF | vmv.s.x      | V   | vector |
| vialuF | vwadd.vx     | V   | vector |
| vialuF | vwadd.wx     | V   | vector |
| vialuF | vwaddu.vx    | V   | vector |
| vialuF | vwaddu.wx    | V   | vector |
| vialuF | vwsub.vx     | V   | vector |
| vialuF | vwsub.wx     | V   | vector |
| vialuF | vwsubu.vx    | V   | vector |
| vialuF | vwsubu.wx    | V   | vector |

## vldu

## vstu

## vppu

table: vppu fu 支持的指令

| 功能单元 | 支持指令            | 扩展  | 描述     |
| ---- | --------------- | --- | ------ |
| vppu | vrgather.vv     | V   | vector |
| vppu | vrgatherei16.vx | V   | vector |
| vppu | vrgather.vx     | V   | vector |
| vppu | vslideup.vx     | V   | vector |
| vppu | vslidedown.vx   | V   | vector |
| vppu | vrgather.vi     | V   | vector |
| vppu | vslideup.vi     | V   | vector |
| vppu | vslidedown.vi   | V   | vector |
| vppu | vmv1r.v         | V   | vector |
| vppu | vmv2r.v         | V   | vector |
| vppu | vmv4r.v         | V   | vector |
| vppu | vmv8r.v         | V   | vector |
| vppu | vcompress.vm    | V   | vector |
| vppu | vslide1up.vx    | V   | vector |
| vppu | vslide1down.vx  | V   | vector |
| vppu | vfslide1up.vf   | V   | vector |
| vppu | vfslide1down.vf | V   | vector |

## vimac

table: vimac fu 支持的指令

| 功能单元  | 支持指令        | 扩展  | 描述     |
| ----- | ----------- | --- | ------ |
| vimac | vsmul.vv    | V   | vector |
| vimac | vsmul.vx    | V   | vector |
| vimac | vmacc.vv    | V   | vector |
| vimac | vmadd.vv    | V   | vector |
| vimac | vmul.vv     | V   | vector |
| vimac | vmulh.vv    | V   | vector |
| vimac | vmulhsu.vv  | V   | vector |
| vimac | vmulhu.vv   | V   | vector |
| vimac | vnmsac.vv   | V   | vector |
| vimac | vnmsub.vv   | V   | vector |
| vimac | vwmacc.vv   | V   | vector |
| vimac | vwmaccsu.vv | V   | vector |
| vimac | vwmaccu.vv  | V   | vector |
| vimac | vwmul.vv    | V   | vector |
| vimac | vwmulsu.vv  | V   | vector |
| vimac | vwmulu.vv   | V   | vector |
| vimac | vmacc.vx    | V   | vector |
| vimac | vmadd.vx    | V   | vector |
| vimac | vmul.vx     | V   | vector |
| vimac | vmulh.vx    | V   | vector |
| vimac | vmulhsu.vx  | V   | vector |
| vimac | vmulhu.vx   | V   | vector |
| vimac | vnmsac.vx   | V   | vector |
| vimac | vnmsub.vx   | V   | vector |
| vimac | vwmacc.vx   | V   | vector |
| vimac | vwmaccsu.vx | V   | vector |
| vimac | vwmaccu.vx  | V   | vector |
| vimac | vwmaccus.vx | V   | vector |
| vimac | vwmul.vx    | V   | vector |
| vimac | vwmulsu.vx  | V   | vector |
| vimac | vwmulu.wx   | V   | vector |

## vidiv

table: vidiv fu 支持的指令

| 功能单元  | 支持指令     | 扩展  | 描述     |
| ----- | -------- | --- | ------ |
| vidiv | vdiv.vv  | V   | vector |
| vidiv | vdivu.vv | V   | vector |
| vidiv | vrem.vv  | V   | vector |
| vidiv | vremu.vv | V   | vector |
| vidiv | vdiv.vx  | V   | vector |
| vidiv | vdivu.vx | V   | vector |
| vidiv | vrem.vx  | V   | vector |
| vidiv | vremu.vx | V   | vector |

## vfalu

table: vfalu fu 支持的指令

| 功能单元  | 支持指令          | 扩展  | 描述     |
| ----- | ------------- | --- | ------ |
| vfalu | vfadd.vv      | V   | vector |
| vfalu | vfsub.vv      | V   | vector |
| vfalu | vfwadd.vv     | V   | vector |
| vfalu | vfwsub.vv     | V   | vector |
| vfalu | vfwadd.wv     | V   | vector |
| vfalu | vfwsub.wv     | V   | vector |
| vfalu | vfmin.vv      | V   | vector |
| vfalu | vfmax.vv      | V   | vector |
| vfalu | vfsgnj.vv     | V   | vector |
| vfalu | vfsgnjn.vv    | V   | vector |
| vfalu | vfsgnjx.vv    | V   | vector |
| vfalu | vmfeq.vv      | V   | vector |
| vfalu | vmfne.vv      | V   | vector |
| vfalu | vmflt.vv      | V   | vector |
| vfalu | vmfle.vv      | V   | vector |
| vfalu | vfclass.v     | V   | vector |
| vfalu | vfredosum.vs  | V   | vector |
| vfalu | vfredusum.vs  | V   | vector |
| vfalu | vfredmax.vs   | V   | vector |
| vfalu | vfredmin.vs   | V   | vector |
| vfalu | vfwredosum.vs | V   | vector |
| vfalu | vfwredusum.vs | V   | vector |
| vfalu | vfadd.vf      | V   | vector |
| vfalu | vfsub.vf      | V   | vector |
| vfalu | vfrsub.vf     | V   | vector |
| vfalu | vfwadd.vf     | V   | vector |
| vfalu | vfwsub.vf     | V   | vector |
| vfalu | vfwadd.wf     | V   | vector |
| vfalu | vfwsub.wf     | V   | vector |
| vfalu | vfmin.vf      | V   | vector |
| vfalu | vfmax.vf      | V   | vector |
| vfalu | vfsgnj.vf     | V   | vector |
| vfalu | vfsgnjn.vf    | V   | vector |
| vfalu | vfsgnjx.vf    | V   | vector |
| vfalu | vmfeq.vf      | V   | vector |
| vfalu | vmfne.vf      | V   | vector |
| vfalu | vmflt.vf      | V   | vector |
| vfalu | vmfle.vf      | V   | vector |
| vfalu | vmfgt.vf      | V   | vector |
| vfalu | vmfge.vf      | V   | vector |
| vfalu | vfmerge.vfm   | V   | vector |
| vfalu | vfmv.v.f      | V   | vector |
| vfalu | vfmv.f.s      | V   | vector |
| vfalu | vfmv.s.f      | V   | vector |

## vfma

table: vfma fu 支持的指令

| 功能单元 | 支持指令        | 扩展  | 描述     |
| ---- | ----------- | --- | ------ |
| vfma | vfmul.vv    | V   | vector |
| vfma | vfwmul.vv   | V   | vector |
| vfma | vfmacc.vv   | V   | vector |
| vfma | vfnmacc.vv  | V   | vector |
| vfma | vfmsac.vv   | V   | vector |
| vfma | vfnmsac.vv  | V   | vector |
| vfma | vfmadd.vv   | V   | vector |
| vfma | vfnmadd.vv  | V   | vector |
| vfma | vfmsub.vv   | V   | vector |
| vfma | vfnmsub.vv  | V   | vector |
| vfma | vfwmacc.vv  | V   | vector |
| vfma | vfwnmacc.vv | V   | vector |
| vfma | vfwmsac.vv  | V   | vector |
| vfma | vfwnmsac.vv | V   | vector |
| vfma | vfmul.vf    | V   | vector |
| vfma | vfwmul.vf   | V   | vector |
| vfma | vfmacc.vf   | V   | vector |
| vfma | vfnmacc.vf  | V   | vector |
| vfma | vfmsac.vf   | V   | vector |
| vfma | vfnmsac.vf  | V   | vector |
| vfma | vfmadd.vf   | V   | vector |
| vfma | vfnmadd.vf  | V   | vector |
| vfma | vfmsub.vf   | V   | vector |
| vfma | vfnmsub.vf  | V   | vector |
| vfma | vfwmacc.vf  | V   | vector |
| vfma | vfwnmacc.vf | V   | vector |
| vfma | vfwmsac.vf  | V   | vector |
| vfma | vfwnmsac.vf | V   | vector |

## vfdiv

table: vfdiv fu 支持的指令

| 功能单元  | 支持指令      | 扩展  | 描述     |
| ----- | --------- | --- | ------ |
| vfdiv | vfdiv.vv  | V   | vector |
| vfdiv | vfsqrt.v  | V   | vector |
| vfdiv | vfdiv.vf  | V   | vector |
| vfdiv | vfrdiv.vf | V   | vector |

## vfcvt

table: vfcvt fu 支持的指令

| 功能单元  | 支持指令              | 扩展  | 描述     |
| ----- | ----------------- | --- | ------ |
| vfcvt | vfrsqrt7.v        | V   | vector |
| vfcvt | vfrec7.v          | V   | vector |
| vfcvt | vfcvt.xu.f.v      | V   | vector |
| vfcvt | vfcvt.x.f.v       | V   | vector |
| vfcvt | vfcvt.rtz.xu.f.v  | V   | vector |
| vfcvt | vfcvt.rtz.x.f.v   | V   | vector |
| vfcvt | vfcvt.f.xu.v      | V   | vector |
| vfcvt | vfwcvt.xu.f.v     | V   | vector |
| vfcvt | vfwcvt.x.f.v      | V   | vector |
| vfcvt | vfwcvt.rtz.xu.f.v | V   | vector |
| vfcvt | vfwcvt.rtz.x.f.v  | V   | vector |
| vfcvt | vfwcvt.f.xu.v     | V   | vector |
| vfcvt | vfwcvt.f.x.v      | V   | vector |
| vfcvt | vfwcvt.f.f.v      | V   | vector |
| vfcvt | vfncvt.xu.f.w     | V   | vector |
| vfcvt | vfncvt.x.f.w      | V   | vector |
| vfcvt | vfncvt.rtz.xu.f.w | V   | vector |
| vfcvt | vfncvt.rtz.x.f.w  | V   | vector |
| vfcvt | vfncvt.f.xu.w     | V   | vector |
| vfcvt | vfncvt.f.x.w      | V   | vector |
| vfcvt | vfncvt.f.f.w      | V   | vector |
| vfcvt | vfncvt.rod.f.f.w  | V   | vector |
