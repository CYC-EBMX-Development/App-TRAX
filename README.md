# tra_x

TRAX 是一款针对使用电动越野摩托车用户的社交应用。

## 规范

### 命名法

- 下划线命名法：只包含小写字母与下滑线，每个单词之间用下划线连接。比如：`user_name`
- 驼峰命名法：每个单词首字母大写，单词之间没有连接符。比如：`UserName`

### 命名规则

**文件**

使用下划线命名法, 比如 `user_name.dart`

**文件夹**

使用下划线命名法，尽量使用复数，比如 `widgets`、`pages`

**类**

使用驼峰命名法， 比如 `UserName`、`UserNameWidget`、`UserNamePage`

**函数**

使用驼峰命名法， 比如 `getUserName`、`getUserNameWidget`、`getUserNamePage`

**全局组件**

以 `Trax` 作为前缀，比如 `TraxButton`、`TraxText` 等

同理对应的文件名是 `trax_button.dart`、`trax_text.dart`

**模块组件**

模块组件可以使用模块名作为前缀，比如登录模块，模块名是 `login`，那么组件名就是 `login_button`、`login_text` 等

## 项目说明

### 公共组件

| 组件名称          | 描述    |
|---------------|-------|
| TraxButton    | 按钮组件  |
| TraxTextField | 输入框组件 |